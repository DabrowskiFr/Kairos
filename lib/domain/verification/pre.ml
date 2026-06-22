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

let simplify_fo (f : Core_syntax.hexpr) : Core_syntax.hexpr =
  Core_fo_simplifier.simplify f

let conj_fo (fs : Core_syntax.hexpr list) : Core_syntax.hexpr option =
  match fs with
  | [] -> None
  | f :: rest -> Some (List.fold_left Core_syntax_builders.mk_hand f rest)

let non_input_program_var_names (n : Abs.node_ir) : ident list =
  List.map
    (fun (v : vdecl) -> v.vname)
    (n.semantics.sem_outputs @ n.semantics.sem_locals)
  |> List.sort_uniq String.compare

let ivar (name : ident) : expr = { expr = EVar name; loc = None }

let stability_formula (name : ident) : Core_syntax.hexpr =
  mk_hexpr (HCmp (REq, hexpr_of_expr (ivar name), mk_hpre_k name 1))

let same_product_state (a : Abs.product_state) (b : Abs.product_state) : bool =
  String.equal a.prog_state b.prog_state
  && a.assume_state_index = b.assume_state_index
  && a.guarantee_state_index = b.guarantee_state_index

let guard_fo_of_transition_core (t : Abs.transition) : Core_syntax.hexpr =
  match t.guard_expr with
  | None -> Core_syntax_builders.mk_hbool true
  | Some guard -> Core_syntax_builders.hexpr_of_expr guard |> simplify_fo

let invariants_of_state (n : Abs.node_ir) : ident -> Core_syntax.hexpr list =
  let by_state = Hashtbl.create 16 in
  List.iter
    (fun (inv : Abs.state_invariant) ->
      if List.mem inv.state n.semantics.sem_states then (
        let existing = Hashtbl.find_opt by_state inv.state |> Option.value ~default:[] in
        Hashtbl.replace by_state inv.state (inv.formula :: existing)))
    n.source_info.state_invariants;
  fun st ->
    (match Hashtbl.find_opt by_state st with
    | None -> []
    | Some xs -> List.sort_uniq compare xs)

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

type node_generation = {
  product_characteristics : Product_characteristics.t;
  initial_product_state : Abs.product_state;
  state_stability : Core_syntax.hexpr list;
  invariant_of_state : ident -> Core_syntax.hexpr option;
}

let compute_generation ~(node : Abs.node_ir) : node_generation =
  let initial_product_state = infer_initial_product_state node in
  {
    product_characteristics = Product_characteristics.build ~node;
    initial_product_state;
    state_stability = List.map stability_formula (non_input_program_var_names node);
    invariant_of_state = (fun st -> conj_fo (invariants_of_state node st));
  }

let add_unique_formula_with_status ~family (f : Core_syntax.hexpr)
    (xs : Abs.summary_formula list) : Abs.summary_formula list * bool =
  if List.exists (fun (x : Abs.summary_formula) -> x.logic = f) xs then (xs, false)
  else (xs @ [ Ir_formula.make ~family f ], true)

let add_formula_family ~record_family ~family_name formulas acc =
  let inserted, acc =
    List.fold_left
      (fun (inserted, acc) f ->
        let acc, was_inserted =
          add_unique_formula_with_status ~family:family_name f acc
        in
        let inserted = if was_inserted then f :: inserted else inserted in
        (inserted, acc))
      ([], acc) formulas
  in
  record_family ~family_name ~candidates:formulas ~inserted:(List.rev inserted);
  acc

let run_node ~record_family (n : Abs.node_ir) : Abs.node_ir =
  let pre_generation = compute_generation ~node:n in
  let summaries =
    List.map
      (fun (pc : Abs.product_step_summary) ->
        let program_guard = guard_fo_of_transition_core pc.identity.program_step in
        let propagation_requires =
          Product_characteristics.entry_facts_of_product_state
            pre_generation.product_characteristics pc.identity.product_src
          |> List.map (Ir_formula.make ~family:"propagation_requires")
        in
        let propagation_requires_formulas =
          List.map (fun (f : Abs.summary_formula) -> f.logic) propagation_requires
        in
        let state_invariants =
          invariants_of_state n pc.identity.product_src.prog_state
        in
        let stability_requires =
          if same_product_state pc.identity.product_src pre_generation.initial_product_state
          then []
          else pre_generation.state_stability
        in
        let requires =
          []
          |> add_formula_family ~record_family
               ~family_name:"state_invariant_requires" state_invariants
          |> add_formula_family ~record_family
               ~family_name:"propagation_requires" propagation_requires_formulas
          |> add_formula_family ~record_family
               ~family_name:"assume_guard_requires" [ pc.identity.assume_guard ]
          |> add_formula_family ~record_family
               ~family_name:"program_guard_requires" [ program_guard ]
          |> add_formula_family ~record_family
               ~family_name:"stability_requires" stability_requires
        in
        { pc with propagation_requires; requires })
      n.summaries
  in
  let init_invariant_candidates = invariants_of_state n n.semantics.sem_init_state in
  let init_invariant_goals =
    add_formula_family ~record_family ~family_name:"init_invariant_goals"
      init_invariant_candidates n.init_invariant_goals
  in
  { n with summaries; init_invariant_goals }

let run_program ?observe_family (p : Abs.node_ir list) : Abs.node_ir list =
  let collector =
    match observe_family with
    | None -> None
    | Some _ -> Some (Ir_fact_family_metrics.create ())
  in
  let record_family ~family_name ~candidates ~inserted =
    match collector with
    | None -> ()
    | Some collector ->
        Ir_fact_family_metrics.add collector ~pass_name:"pre" ~family_name
          ~candidates ~inserted
  in
  let result = List.map (run_node ~record_family) p in
  (match (collector, observe_family) with
  | Some collector, Some observer -> Ir_fact_family_metrics.emit collector observer
  | _ -> ());
  result
