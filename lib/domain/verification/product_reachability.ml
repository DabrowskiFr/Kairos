(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *---------------------------------------------------------------------------*)

open Core_syntax
open Core_syntax_builders

module Abs = Ir

type t = {
  reachable : (Abs.product_state, unit) Hashtbl.t;
  known_states : (Abs.product_state, unit) Hashtbl.t;
}

let simplify_fo (f : Core_syntax.hexpr) : Core_syntax.hexpr =
  Core_fo_simplifier.simplify f

let is_hfalse (f : Core_syntax.hexpr) : bool =
  match (simplify_fo f).hexpr with HLitBool false -> true | _ -> false

let is_htrue (f : Core_syntax.hexpr) : bool =
  match (simplify_fo f).hexpr with HLitBool true -> true | _ -> false

let same_product_state (a : Abs.product_state) (b : Abs.product_state) : bool =
  String.equal a.prog_state b.prog_state
  && a.assume_state_index = b.assume_state_index
  && a.guarantee_state_index = b.guarantee_state_index

let add_unique_formula (f : Core_syntax.hexpr)
    (xs : Abs.summary_formula list) : Abs.summary_formula list =
  if List.exists (fun (x : Abs.summary_formula) -> x.logic = f) xs then xs
  else xs @ [ Ir_formula.make f ]

let guard_fo_of_transition (t : Abs.transition) : Core_syntax.hexpr =
  match t.guard_expr with
  | None -> mk_hbool true
  | Some guard -> hexpr_of_expr guard |> simplify_fo

let infer_initial_product_state (node : Abs.node_ir) : Abs.product_state =
  let candidates =
    node.summaries
    |> List.map (fun (pc : Abs.product_step_summary) -> pc.identity.product_src)
    |> List.filter (fun (st : Abs.product_state) ->
           String.equal st.prog_state node.semantics.sem_init_state)
    |> List.sort_uniq Stdlib.compare
  in
  match
    List.find_opt
      (fun (st : Abs.product_state) -> st.assume_state_index = 0 && st.guarantee_state_index = 0)
      candidates
  with
  | Some st -> st
  | None -> (
      match candidates with
      | st :: _ -> st
      | [] ->
          {
            Abs.prog_state = node.semantics.sem_init_state;
            assume_state_index = 0;
            guarantee_state_index = 0;
          })

let flatten_bool op (f : Core_syntax.hexpr) : Core_syntax.hexpr list =
  let rec loop acc h =
    match h.hexpr with
    | HBin (op', a, b) when op = op' -> loop (loop acc b) a
    | _ -> h :: acc
  in
  List.rev (loop [] f)

type bool_lit = { name : ident; value : bool }

let bool_lit_of_hexpr (h : Core_syntax.hexpr) : bool_lit option =
  match h.hexpr with
  | HVar name -> Some { name; value = true }
  | HUn (Not, { hexpr = HVar name; _ }) -> Some { name; value = false }
  | HCmp (REq, { hexpr = HVar name; _ }, { hexpr = HLitBool value; _ })
  | HCmp (REq, { hexpr = HLitBool value; _ }, { hexpr = HVar name; _ }) ->
      Some { name; value }
  | HCmp (RNeq, { hexpr = HVar name; _ }, { hexpr = HLitBool value; _ })
  | HCmp (RNeq, { hexpr = HLitBool value; _ }, { hexpr = HVar name; _ }) ->
      Some { name; value = not value }
  | HUn (Not, { hexpr = HCmp (REq, { hexpr = HVar name; _ }, { hexpr = HLitBool value; _ }); _ })
  | HUn (Not, { hexpr = HCmp (REq, { hexpr = HLitBool value; _ }, { hexpr = HVar name; _ }); _ }) ->
      Some { name; value = not value }
  | _ -> None

let exact_complement (a : Core_syntax.hexpr) (b : Core_syntax.hexpr) : bool =
  match (a.hexpr, b.hexpr) with
  | HUn (Not, inner), _ when inner = b -> true
  | _, HUn (Not, inner) when inner = a -> true
  | _ -> false

let and_has_contradiction (xs : Core_syntax.hexpr list) : bool =
  let lits = Hashtbl.create 16 in
  let lit_contradiction =
    xs
    |> List.exists (fun h ->
           match bool_lit_of_hexpr h with
           | None -> false
           | Some lit -> (
               match Hashtbl.find_opt lits lit.name with
               | Some previous when previous <> lit.value -> true
               | _ ->
                   Hashtbl.replace lits lit.name lit.value;
                   false))
  in
  lit_contradiction
  || List.exists
       (fun a -> List.exists (fun b -> exact_complement a b) xs)
       xs

let contradictory_context (context : Core_syntax.hexpr list) (candidate : Core_syntax.hexpr) :
    bool =
  let xs = context @ flatten_bool And candidate in
  is_hfalse (List.fold_left mk_hand (mk_hbool true) xs) || and_has_contradiction xs

let conjunction_obviously_false (f : Core_syntax.hexpr) : bool =
  let f = simplify_fo f in
  if is_hfalse f then true
  else
    let conjuncts = flatten_bool And f in
    and_has_contradiction conjuncts
    || List.exists
         (fun h ->
           match h.hexpr with
           | HBin (Or, _, _) ->
               flatten_bool Or h
               |> List.for_all (contradictory_context (List.filter (( != ) h) conjuncts))
           | _ -> false)
         conjuncts

let edge_may_fire (pc : Abs.product_step_summary) (case : Abs.safe_product_case) : bool =
  let guard =
    mk_hand
      (guard_fo_of_transition pc.identity.program_step)
      (mk_hand pc.identity.assume_guard case.admissible_guard.logic)
    |> simplify_fo
  in
  not (conjunction_obviously_false guard)

let collect_known_states (node : Abs.node_ir) : (Abs.product_state, unit) Hashtbl.t =
  let tbl = Hashtbl.create 32 in
  let add st = Hashtbl.replace tbl st () in
  List.iter
    (fun (pc : Abs.product_step_summary) ->
      add pc.identity.product_src;
      List.iter (fun (case : Abs.safe_product_case) -> add case.product_dst) pc.safe_cases;
      List.iter (fun (case : Abs.unsafe_product_case) -> add case.product_dst) pc.unsafe_cases)
    node.summaries;
  tbl

let build ~(node : Abs.node_ir) : t =
  let known_states = collect_known_states node in
  let reachable = Hashtbl.create 32 in
  let mark st =
    if Hashtbl.mem reachable st then false
    else (
      Hashtbl.replace reachable st ();
      true)
  in
  ignore (mark (infer_initial_product_state node));
  let changed = ref true in
  while !changed do
    changed := false;
    List.iter
      (fun (pc : Abs.product_step_summary) ->
        if Hashtbl.mem reachable pc.identity.product_src then
          List.iter
            (fun (case : Abs.safe_product_case) ->
              if edge_may_fire pc case && mark case.product_dst then changed := true)
            pc.safe_cases)
      node.summaries
  done;
  { reachable; known_states }

let formula_of_product_state (t : t) (st : Abs.product_state) : Core_syntax.hexpr =
  if not (Hashtbl.mem t.known_states st) then mk_hbool true
  else mk_hbool (Hashtbl.mem t.reachable st)

let local_requires_of_product_state (t : t) (st : Abs.product_state) : Core_syntax.hexpr list =
  let f = formula_of_product_state t st in
  if is_htrue f then [] else [ f ]

let preservation_ensures (t : t) (pc : Abs.product_step_summary) : Core_syntax.hexpr list =
  pc.safe_cases
  |> List.filter_map (fun (case : Abs.safe_product_case) ->
         let dst_reach = formula_of_product_state t case.product_dst in
         if is_htrue dst_reach then None
         else Some (mk_himp case.admissible_guard.logic dst_reach |> simplify_fo))
  |> List.filter (fun f -> not (is_htrue f))
  |> List.sort_uniq Stdlib.compare

let run_node (n : Abs.node_ir) : Abs.node_ir =
  let reachability = build ~node:n in
  let summaries =
    List.map
      (fun (pc : Abs.product_step_summary) ->
        let ensures =
          List.fold_left
            (fun acc f -> add_unique_formula f acc)
            pc.ensures
            (preservation_ensures reachability pc)
        in
        { pc with ensures })
      n.summaries
  in
  { n with summaries }

let run_program (p : Abs.node_ir list) : Abs.node_ir list = List.map run_node p
