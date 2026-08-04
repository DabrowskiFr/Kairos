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
open Kr_domain_core_syntax
open Kr_domain_core_syntax_builders

module Abs = Kr_verification_ir

let simplify_fo (f : Kr_domain_core_syntax.historical Kr_domain_core_syntax.hexpr) : Kr_domain_core_syntax.historical Kr_domain_core_syntax.hexpr =
  Kr_domain_core_formula_simplifier.simplify f

let conj_fo (fs : Kr_domain_core_syntax.historical Kr_domain_core_syntax.hexpr list) : Kr_domain_core_syntax.historical Kr_domain_core_syntax.hexpr option =
  match fs with
  | [] -> None
  | f :: rest -> Some (List.fold_left Kr_domain_core_syntax_builders.mk_hand f rest)

let non_input_program_var_names (n : Kr_domain_core_syntax.historical Abs.node_ir) : ident list =
  List.map
    (fun (v : vdecl) -> v.vname)
    (n.semantics.sem_outputs @ n.semantics.sem_locals)
  |> List.sort_uniq String.compare

let reject_current_inputs_in_propagation_requires ~(node_name : ident)
    ~(input_names : ident list) (f : Kr_domain_core_syntax.historical Kr_domain_core_syntax.hexpr) : Kr_domain_core_syntax.historical Kr_domain_core_syntax.hexpr =
  Fo_current_input.require_no_current_input
    ~context:(Printf.sprintf "pre: propagation requirements for node %s" node_name)
    ~input_names f

let ivar (name : ident) : expr = { expr = EVar name; loc = None }

let stability_formula (name : ident) : Kr_domain_core_syntax.historical Kr_domain_core_syntax.hexpr =
  mk_hexpr
    (HCmp
       ( REq,
         hexpr_of_expr (ivar name)
         |> Kr_domain_core_syntax.historical_of_history_free,
         mk_hpre_k name 1 ))

let guard_fo_of_transition_core (t : Abs.transition) : Kr_domain_core_syntax.historical Kr_domain_core_syntax.hexpr =
  match t.guard_expr with
  | None -> Kr_domain_core_syntax_builders.mk_hbool true
  | Some guard ->
      Kr_domain_core_syntax_builders.hexpr_of_expr guard
      |> Kr_domain_core_syntax.historical_of_history_free |> simplify_fo

let invariants_of_state (n : Kr_domain_core_syntax.historical Abs.node_ir) : ident -> Kr_domain_core_syntax.historical Kr_domain_core_syntax.hexpr list =
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
    | Some xs -> List.rev xs)

type node_generation = {
  product_invariants : Product_invariant.t list;
  state_stability : Kr_domain_core_syntax.historical Kr_domain_core_syntax.hexpr list;
  invariant_of_state : ident -> Kr_domain_core_syntax.historical Kr_domain_core_syntax.hexpr option;
}

let compute_generation ~product_invariants
    ~(node : Kr_domain_core_syntax.historical Abs.node_ir) : node_generation =
  {
    product_invariants;
    state_stability = List.map stability_formula (non_input_program_var_names node);
    invariant_of_state = (fun st -> conj_fo (invariants_of_state node st));
  }

let add_formula_family ~record_family ~family_name formulas acc =
  record_family ~family_name ~candidates:formulas ~inserted:formulas;
  acc @ List.map (Ir_formula.make ~family:family_name) formulas

let run_node ~record_family ~product_invariants
    (n : Kr_domain_core_syntax.historical Abs.node_ir) :
    Kr_domain_core_syntax.historical Abs.node_ir =
  let pre_generation =
    compute_generation ~product_invariants ~node:n
  in
  let input_names = Fo_current_input.input_names n.semantics.sem_inputs in
  let summaries =
    List.map
      (fun (pc : Kr_domain_core_syntax.historical Abs.product_step_summary) ->
        let program_guard = guard_fo_of_transition_core pc.identity.program_step in
        let product_src = Abs.product_source pc in
        let propagation_requires =
          Product_invariant.entry_facts
            pre_generation.product_invariants
            product_src
          |> List.fold_left
               (fun accumulated (family, formulas) ->
                 let formulas =
                   List.map
                     (reject_current_inputs_in_propagation_requires
                        ~node_name:n.semantics.sem_nname
                        ~input_names)
                     formulas
                 in
                 add_formula_family ~record_family
                   ~family_name:(family ^ "_requires")
                   formulas accumulated)
               pc.propagation_requires
        in
        let state_invariants =
          invariants_of_state n product_src.prog_state
        in
        let requires =
          []
          |> add_formula_family ~record_family
               ~family_name:"state_invariant_requires" state_invariants
          |> add_formula_family ~record_family
               ~family_name:"program_guard_requires" [ program_guard ]
          |> add_formula_family ~record_family
               ~family_name:"stability_requires" pre_generation.state_stability
        in
        { pc with propagation_requires; requires })
      n.summaries
  in
  { n with summaries }

let run_program ?observe_family ~product_invariants
    (p : Kr_domain_core_syntax.historical Abs.node_ir list) :
    Kr_domain_core_syntax.historical Abs.node_ir list =
  let collector =
    match observe_family with
    | None -> None
    | Some _ -> Some (Kr_verification_fact_metrics.create ())
  in
  let record_family ~family_name ~candidates ~inserted =
    match collector with
    | None -> ()
    | Some collector ->
        Kr_verification_fact_metrics.add collector ~pass_name:"pre" ~family_name
          ~candidates ~inserted
  in
  let result =
    List.map2
      (fun product_invariants node ->
        run_node ~record_family ~product_invariants node)
      product_invariants p
  in
  (match (collector, observe_family) with
  | Some collector, Some observer -> Kr_verification_fact_metrics.emit collector observer
  | _ -> ());
  result
