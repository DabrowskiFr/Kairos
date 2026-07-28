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
open Fo_time

module Abs = Ir
module StringSet = Set.Make (String)

type entry = {
  product_state : Abs.product_state;
  entry_fact : Core_syntax.historical Core_syntax.hexpr;
}

type t = {
  entries : entry list;
  by_state : (string, entry) Hashtbl.t;
}

let simplify_fo (f : Core_syntax.historical Core_syntax.hexpr) : Core_syntax.historical Core_syntax.hexpr =
  Core_fo_simplifier.simplify f

let product_state_key (st : Abs.product_state) =
  Printf.sprintf "%s/a%d/g%d" st.prog_state st.assume_state_index
    st.guarantee_state_index

let rec assigned_vars_of_stmt (stmt : Core_syntax.stmt) : StringSet.t =
  match stmt.stmt with
  | SAssign (name, _) -> StringSet.singleton name
  | SAssert _ | SSkip -> StringSet.empty
  | SIf (_, then_branch, else_branch) ->
      StringSet.union
        (assigned_vars_of_stmts then_branch)
        (assigned_vars_of_stmts else_branch)
  | SWhile (_, _, _, body) -> assigned_vars_of_stmts body
  | SMatch (_, branches, default_branch) ->
      List.fold_left
        (fun assigned (_, body) ->
          StringSet.union assigned (assigned_vars_of_stmts body))
        (assigned_vars_of_stmts default_branch) branches
  | SCall (_, _, destinations) ->
      List.fold_left
        (fun assigned name -> StringSet.add name assigned)
        StringSet.empty destinations

and assigned_vars_of_stmts (stmts : Core_syntax.stmt list) : StringSet.t =
  List.fold_left
    (fun assigned stmt ->
      StringSet.union assigned (assigned_vars_of_stmt stmt))
    StringSet.empty stmts

let is_htrue (f : Core_syntax.historical Core_syntax.hexpr) : bool =
  match (simplify_fo f).hexpr with HLitBool true -> true | _ -> false

let same_product_state (a : Abs.product_state) (b : Abs.product_state) : bool =
  String.equal a.prog_state b.prog_state
  && a.assume_state_index = b.assume_state_index
  && a.guarantee_state_index = b.guarantee_state_index

let formula_key (f : Core_syntax.historical Core_syntax.hexpr) : string =
  Core_fo_simplifier.key_of_hexpr (simplify_fo f)

let same_formula (a : Core_syntax.historical Core_syntax.hexpr) (b : Core_syntax.historical Core_syntax.hexpr) : bool =
  String.equal (formula_key a) (formula_key b)

let dedup_formulas
    (xs : Core_syntax.historical Core_syntax.hexpr list) :
    Core_syntax.historical Core_syntax.hexpr list =
  let keyed =
    List.map (fun f -> (formula_key f, simplify_fo f)) xs
  in
  keyed
  |> List.sort_uniq (fun (ka, _) (kb, _) ->
         String.compare ka kb)
  |> List.map snd

let disj_fo (fs : Core_syntax.historical Core_syntax.hexpr list) : Core_syntax.historical Core_syntax.hexpr option =
  match dedup_formulas fs with
  | [] -> None
  | f :: rest -> Some (List.fold_left mk_hor f rest |> simplify_fo)

let infer_initial_product_state (node : Core_syntax.historical Abs.node_ir) : Abs.product_state =
  let candidates =
    node.summaries
    |> List.map (fun (pc : Core_syntax.historical Abs.product_step_summary) -> pc.identity.product_src)
    |> List.filter (fun (st : Abs.product_state) ->
           String.equal st.prog_state node.semantics.sem_init_state)
    |> List.sort_uniq Stdlib.compare
  in
  match
    List.find_opt
      (fun (st : Abs.product_state) ->
        st.assume_state_index = 0 && st.guarantee_state_index = 0)
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

let input_names (n : Core_syntax.historical Abs.node_ir) : ident list =
  List.map (fun (v : vdecl) -> v.vname) n.semantics.sem_inputs

let is_input_of_node (n : Core_syntax.historical Abs.node_ir) : ident -> bool =
  let names = input_names n in
  fun x -> List.mem x names

let non_input_program_names (n : Core_syntax.historical Abs.node_ir) : ident list =
  n.semantics.sem_outputs @ n.semantics.sem_locals
  |> List.map (fun (v : vdecl) -> v.vname)
  |> List.sort_uniq String.compare

let control_annotation_formula (n : Core_syntax.historical Abs.node_ir) (state : ident) :
    Core_syntax.historical Core_syntax.hexpr =
  n.source_info.state_invariants
  |> List.filter_map (fun (inv : Abs.state_invariant) ->
         if String.equal inv.state state then Some inv.formula else None)
  |> List.fold_left mk_hand (mk_hbool true)
  |> simplify_fo

let lookup_symbolic_value env name =
  List.assoc_opt name env |> Option.join

let bind_symbolic_value env name value =
  (name, value) :: List.remove_assoc name env

let rec post_expr_of_expr env (expr : Core_syntax.expr) :
    Core_syntax.historical Core_syntax.hexpr option =
  let recurse = post_expr_of_expr env in
  let map2 make left right =
    match (recurse left, recurse right) with
    | Some left, Some right -> Some (make left right)
    | _ -> None
  in
  match expr.expr with
  | ELitInt value -> Some (mk_hint value)
  | ELitBool value -> Some (mk_hbool value)
  | ELitEnum value -> Some (mk_hexpr (HLitEnum value))
  | EVar name -> lookup_symbolic_value env name
  | EFunCall (name, arguments) ->
      let rec map_arguments acc = function
        | [] -> Some (List.rev acc)
        | argument :: rest -> (
            match recurse argument with
            | None -> None
            | Some argument -> map_arguments (argument :: acc) rest)
      in
      Option.map (fun arguments -> mk_hexpr (HFunCall (name, arguments)))
        (map_arguments [] arguments)
  | EBin (operator, left, right) ->
      map2 (fun left right -> mk_hexpr (HBin (operator, left, right)))
        left right
  | ECmp (operator, left, right) ->
      map2 (fun left right -> mk_hexpr (HCmp (operator, left, right)))
        left right
  | EUn (operator, argument) ->
      Option.map (fun argument -> mk_hexpr (HUn (operator, argument)))
        (recurse argument)

let forget_assigned env statements =
  StringSet.fold
    (fun name env -> bind_symbolic_value env name None)
    (assigned_vars_of_stmts statements) env

let rec symbolic_execute_statement env (statement : Core_syntax.stmt) =
  match statement.stmt with
  | SAssign (name, rhs) ->
      bind_symbolic_value env name (post_expr_of_expr env rhs)
  | SAssert _ | SSkip -> env
  | SIf _ | SWhile _ | SMatch _ -> forget_assigned env [ statement ]
  | SCall (_, _, destinations) ->
      List.fold_left
        (fun env name -> bind_symbolic_value env name None)
        env destinations

let symbolic_execute_statements env statements =
  List.fold_left symbolic_execute_statement env statements

let transition_effect_formula ~(node : Core_syntax.historical Abs.node_ir)
    (transition : Abs.transition) : Core_syntax.historical Core_syntax.hexpr =
  let inputs = input_names node in
  let non_inputs = non_input_program_names node in
  let initial =
    List.map (fun name -> (name, Some (mk_hvar name))) inputs
    @ List.map (fun name -> (name, Some (mk_hpre_k name 1))) non_inputs
  in
  let final = symbolic_execute_statements initial transition.body_stmts in
  non_inputs
  |> List.filter_map (fun name ->
         Option.map
           (fun value -> mk_hexpr (HCmp (REq, mk_hvar name, value)))
           (lookup_symbolic_value final name))
  |> List.fold_left mk_hand (mk_hbool true)
  |> simplify_fo

let guard_fo_of_transition (t : Abs.transition) : Core_syntax.historical Core_syntax.hexpr =
  match t.guard_expr with
  | None -> mk_hbool true
  | Some guard ->
      hexpr_of_expr guard |> Core_syntax.historical_of_history_free
      |> simplify_fo

let incoming_post_formula ~(node : Core_syntax.historical Abs.node_ir)
    (summary : Core_syntax.historical Abs.product_step_summary)
    (case : Core_syntax.historical Abs.safe_product_case) : Core_syntax.historical Core_syntax.hexpr =
  let is_input = is_input_of_node node in
  let program_guard = guard_fo_of_transition summary.identity.program_step in
  let source_annotation =
    control_annotation_formula node summary.identity.product_src.prog_state
  in
  let body_effect =
    transition_effect_formula ~node summary.identity.program_step
  in
  mk_hand
    (mk_hand
      (mk_hand
        (mk_hand
          (shift_formula_entry_to_post ~is_input source_annotation)
          (shift_formula_entry_to_post ~is_input program_guard))
        summary.identity.assume_guard)
      case.admissible_guard.logic)
    body_effect
  |> simplify_fo

type incoming_entry = {
  dst : Abs.product_state;
  program_entry_formulas : Core_syntax.historical Core_syntax.hexpr list;
}

let states_needing_characteristic (node : Core_syntax.historical Abs.node_ir) : Abs.product_state list =
  node.summaries
  |> List.filter (fun (summary : Core_syntax.historical Abs.product_step_summary) ->
         summary.unsafe_cases <> [])
  |> List.map (fun (summary : Core_syntax.historical Abs.product_step_summary) ->
         summary.identity.product_src)
  |> List.sort_uniq Stdlib.compare

let needs_characteristic
    ~(states : Abs.product_state list) (state : Abs.product_state) : bool =
  List.exists (same_product_state state) states

let add_incoming dst ~program_entry_formula incoming =
  let rec loop acc = function
    | [] ->
        List.rev
          ({
             dst;
             program_entry_formulas = [ program_entry_formula ];
           }
            :: acc)
    | entry :: rest when same_product_state dst entry.dst ->
        List.rev_append acc
          ({
             entry with
             program_entry_formulas =
               program_entry_formula :: entry.program_entry_formulas;
           }
            :: rest)
    | x :: rest -> loop (x :: acc) rest
  in
  loop [] incoming

let build_table entries =
  let by_state = Hashtbl.create (List.length entries * 2 + 1) in
  List.iter
    (fun (entry : entry) ->
      Hashtbl.replace by_state (product_state_key entry.product_state) entry)
    entries;
  { entries; by_state }

let build ~(node : Core_syntax.historical Abs.node_ir) : t =
  let is_input = is_input_of_node node in
  let initial_product_state = infer_initial_product_state node in
  let characteristic_states = states_needing_characteristic node in
  let incoming =
    List.fold_left
      (fun acc (pc : Core_syntax.historical Abs.product_step_summary) ->
        List.fold_left
          (fun acc (case : Core_syntax.historical Abs.safe_product_case) ->
            let program_post_formula =
              incoming_post_formula ~node pc case
            in
            let program_entry_formula =
              shift_formula_forward_inputs ~is_input program_post_formula
              |> simplify_fo
            in
            add_incoming case.product_dst ~program_entry_formula acc)
          acc pc.safe_cases)
      [] node.summaries
  in
  let entries =
    incoming
    |> List.filter_map (fun entry ->
         let dst = entry.dst in
           if
             same_product_state dst initial_product_state
             || not (needs_characteristic ~states:characteristic_states dst)
           then None
           else
             match disj_fo entry.program_entry_formulas with
             | None -> None
             | Some entry_fact ->
                 let entry_fact = simplify_fo entry_fact in
                 if is_htrue entry_fact then None
                 else
                   Some { product_state = dst; entry_fact })
    |> List.sort_uniq Stdlib.compare
  in
  build_table entries

let entry_of_product_state (t : t) (st : Abs.product_state) : entry option =
  Hashtbl.find_opt t.by_state (product_state_key st)

let entry_facts_of_product_state (t : t) (st : Abs.product_state) :
    Core_syntax.historical Core_syntax.hexpr list =
  match entry_of_product_state t st with
  | None -> []
  | Some entry -> [ entry.entry_fact ]

let preservation_ensures (t : t) ~(node : Core_syntax.historical Abs.node_ir)
    (pc : Core_syntax.historical Abs.product_step_summary) : Core_syntax.historical Core_syntax.hexpr list =
  pc.safe_cases
  |> List.filter_map (fun (case : Core_syntax.historical Abs.safe_product_case) ->
         match entry_of_product_state t case.product_dst with
         | None -> None
         | Some _ ->
             let contribution = incoming_post_formula ~node pc case in
             if same_formula case.admissible_guard.logic contribution then None
             else
               Some
                 (mk_himp case.admissible_guard.logic contribution
                 |> simplify_fo))
  |> List.filter (fun f -> not (is_htrue f))
