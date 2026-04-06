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

open Ast
open Fo_specs
open Fo_time
open Formula_origin
open Ast_pretty

module Abs = Ir

let simplify_fo (f : Fo_formula.t) : Fo_formula.t =
  match Fo_z3_solver.simplify_fo_formula f with Some simplified -> simplified | None -> f

let dedup_formulas (xs : Fo_formula.t list) : Fo_formula.t list = List.sort_uniq compare xs

let disj_fo (fs : Fo_formula.t list) : Fo_formula.t option =
  match fs with
  | [] -> None
  | f :: rest -> Some (List.fold_left (fun acc x -> Fo_formula.FOr (acc, x)) f rest |> simplify_fo)

let input_names (n : Abs.node_ir) : ident list =
  List.map (fun (v : vdecl) -> v.vname) n.context.semantics.sem_inputs

let is_input_of_node (n : Abs.node_ir) : ident -> bool =
  let names = input_names n in
  fun x -> List.mem x names

let non_input_program_var_names (n : Abs.node_ir) : ident list =
  List.map
    (fun (v : vdecl) -> v.vname)
    (n.context.semantics.sem_outputs @ n.context.semantics.sem_locals)
  |> List.sort_uniq String.compare

let ivar (name : ident) : iexpr = { iexpr = IVar name; loc = None }

let stability_formula (name : ident) : Fo_formula.t =
  Fo_formula.FAtom (FRel (HNow (ivar name), REq, HPreK (ivar name, 1)))

let same_product_state (a : Abs.product_state) (b : Abs.product_state) : bool =
  String.equal a.prog_state b.prog_state
  && a.assume_state_index = b.assume_state_index
  && a.guarantee_state_index = b.guarantee_state_index

let guard_fo_of_transition_core (t : Abs.transition) : Fo_formula.t =
  match t.guard_iexpr with
  | None -> Fo_formula.FTrue
  | Some guard -> Fo_specs.iexpr_to_fo_with_atoms [] guard |> simplify_fo

let rec iexpr_mentions_current_input ~(is_input : ident -> bool) (e : Ast.iexpr) =
  match e.iexpr with
  | IVar name -> is_input name
  | ILitInt _ | ILitBool _ -> false
  | IPar inner | IUn (_, inner) -> iexpr_mentions_current_input ~is_input inner
  | IBin (_, a, b) ->
      iexpr_mentions_current_input ~is_input a || iexpr_mentions_current_input ~is_input b

let hexpr_mentions_current_input ~(is_input : ident -> bool) = function
  | HNow e -> iexpr_mentions_current_input ~is_input e
  | HPreK _ -> false

let rec ltl_mentions_current_input ~(is_input : ident -> bool) (f : Ast.ltl) =
  match f with
  | LTrue | LFalse -> false
  | LAtom (FRel (a, _, b)) ->
      hexpr_mentions_current_input ~is_input a || hexpr_mentions_current_input ~is_input b
  | LAtom (FPred (_, hs)) -> List.exists (hexpr_mentions_current_input ~is_input) hs
  | LNot inner | LX inner | LG inner -> ltl_mentions_current_input ~is_input inner
  | LAnd (a, b) | LOr (a, b) | LImp (a, b) | LW (a, b) ->
      ltl_mentions_current_input ~is_input a || ltl_mentions_current_input ~is_input b

let reject_current_input_invariant ~(node : Abs.node_ir) (inv : invariant_state_rel) : unit =
  let is_input = is_input_of_node node in
  if ltl_mentions_current_input ~is_input inv.formula then
    failwith
      (Printf.sprintf
         "State invariant for node %s in state %s mentions a current input (HNow on an input), \
          which is forbidden for node-entry invariants: %s"
         node.context.semantics.sem_nname inv.state (string_of_ltl inv.formula))

let invariant_of_state (n : Abs.node_ir) : ident -> Fo_formula.t option =
  let by_state = Hashtbl.create 16 in
  List.iter
    (fun (inv : invariant_state_rel) ->
      if List.mem inv.state n.context.semantics.sem_states then (
        reject_current_input_invariant ~node:n inv;
        let inv_fo = fo_formula_of_non_temporal_ltl_exn inv.formula in
        let existing = Hashtbl.find_opt by_state inv.state |> Option.value ~default:[] in
        Hashtbl.replace by_state inv.state (inv_fo :: existing)))
    n.context.source_info.state_invariants;
  fun st ->
    (match Hashtbl.find_opt by_state st with
    | None -> None
    | Some xs -> conj_fo (List.sort_uniq compare xs))

let infer_initial_product_state (node : Abs.node_ir) : Abs.product_state =
  let candidates =
    node.summaries
    |> List.map (fun (pc : Abs.product_step_summary) -> pc.identity.product_src)
    |> List.filter (fun (st : Abs.product_state) ->
           String.equal st.prog_state node.context.semantics.sem_init_state)
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
            Abs.prog_state = node.context.semantics.sem_init_state;
            assume_state_index = 0;
            guarantee_state_index = 0;
          })

let guarantee_pre_of_product_state ~(node : Abs.node_ir) ~(initial_product_state : Abs.product_state) :
    Abs.product_state -> Fo_formula.t option =
  let is_input = is_input_of_node node in
  let by_dst = ref [] in
  let add dst formulas =
    let rec loop acc = function
      | [] -> List.rev ((dst, formulas) :: acc)
      | (dst', prev) :: rest when same_product_state dst dst' ->
          List.rev_append acc ((dst, dedup_formulas (formulas @ prev)) :: rest)
      | x :: rest -> loop (x :: acc) rest
    in
    by_dst := loop [] !by_dst
  in
  List.iter
    (fun (pc : Abs.product_step_summary) ->
      List.iter
        (fun (case : Abs.safe_product_case) ->
          let propagated = shift_formula_forward_inputs ~is_input case.admissible_guard.logic in
          add case.product_dst [ propagated ])
        pc.safe_cases)
    node.summaries;
  fun st ->
    let from_ensures =
      List.find_map
        (fun (dst, fs) -> if same_product_state dst st then Some fs else None)
        !by_dst
      |> Option.value ~default:[]
    in
    let from_ensures =
      if same_product_state st initial_product_state then Fo_formula.FTrue :: from_ensures else from_ensures
    in
    disj_fo from_ensures

type t = {
  guarantee_pre_of_product_state : Abs.product_state -> Fo_formula.t option;
  initial_product_state : Abs.product_state;
  state_stability : Fo_formula.t list;
  invariant_of_state : Ast.ident -> Fo_formula.t option;
}

let build ~(node : Abs.node_ir) : t =
  let initial_product_state = infer_initial_product_state node in
  {
    guarantee_pre_of_product_state = guarantee_pre_of_product_state ~node ~initial_product_state;
    initial_product_state;
    state_stability = List.map stability_formula (non_input_program_var_names node);
    invariant_of_state = invariant_of_state node;
  }

let add_unique_formula (origin : Formula_origin.t) (f : Fo_formula.t)
    (xs : Abs.summary_formula list) : Abs.summary_formula list =
  if List.exists (fun (x : Abs.summary_formula) -> x.logic = f) xs then xs
  else xs @ [ Ir_formula.with_origin origin f ]

let apply ~(pre_generation : t) (n : Abs.node_ir) : Abs.node_ir =
  let summaries =
    List.map
      (fun (pc : Abs.product_step_summary) ->
        let program_guard = guard_fo_of_transition_core pc.identity.program_step in
        let requires =
          []
          |> fun acc ->
          (match pre_generation.invariant_of_state pc.identity.product_src.prog_state with
          | None -> acc
          | Some inv -> add_unique_formula Invariant inv acc)
          |> fun acc ->
          (match pre_generation.guarantee_pre_of_product_state pc.identity.product_src with
          | None -> acc
          | Some inv -> add_unique_formula GuaranteePropagation inv acc)
          |> add_unique_formula AssumeAutomaton pc.identity.assume_guard
          |> add_unique_formula ProgramGuard program_guard
          |> fun acc ->
          if same_product_state pc.identity.product_src pre_generation.initial_product_state then acc
          else List.fold_left (fun acc f -> add_unique_formula StateStability f acc) acc pre_generation.state_stability
        in
        { pc with requires })
      n.summaries
  in
  let init_invariant_goals =
    match pre_generation.invariant_of_state n.context.semantics.sem_init_state with
    | None -> n.init_invariant_goals
    | Some inv ->
        if List.exists (fun (f : Abs.summary_formula) -> f.logic = inv) n.init_invariant_goals then
          n.init_invariant_goals
        else
          n.init_invariant_goals @ [ Ir_formula.with_origin Formula_origin.Invariant inv ]
  in
  { n with summaries; init_invariant_goals }

let build_program (p : Abs.node_ir list) : (Ast.ident * t) list =
  List.map (fun (n : Abs.node_ir) -> (n.context.semantics.sem_nname, build ~node:n)) p

let apply_program ~(pre_generations : (Ast.ident * t) list) (p : Abs.node_ir list) : Abs.node_ir list =
  List.map
    (fun (n : Abs.node_ir) ->
      let pre_generation =
        match List.assoc_opt n.context.semantics.sem_nname pre_generations with
        | Some pg -> pg
        | None ->
            failwith
              (Printf.sprintf "Missing pre generation for normalized node %s"
                 n.context.semantics.sem_nname)
      in
      apply ~pre_generation n)
    p
