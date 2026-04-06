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

module Abs = Ir

let simplify_fo (f : Fo_formula.t) : Fo_formula.t =
  match Fo_z3_solver.simplify_fo_formula f with Some simplified -> simplified | None -> f

(** Convert an optional imperative guard to a first-order formula. *)
let guard_fo (g : Ast.iexpr option) : Fo_formula.t =
  match g with
  | None -> Fo_formula.FTrue
  | Some e ->
      Fo_specs.iexpr_to_fo_with_atoms [] e |> simplify_fo

(** Build a raw transition from a finalized abstract transition.
    requires/ensures are intentionally omitted — they belong to pass 4. *)
let raw_transition_of_abs (t : Abs.transition) : Ir_proof_views.raw_transition =
  {
    core =
      {
        Ir.src_state = t.src_state;
        dst_state = t.dst_state;
        guard_iexpr = t.guard_iexpr;
        body_stmts = t.body_stmts;
      };
    guard = guard_fo t.guard_iexpr;
  }

(** Build pre_k map from a finalized abstract node. *)
let compute_pre_k_map (node : Abs.node_ir) : (Ast.hexpr * Temporal_support.pre_k_info) list =
  let summary_formulas =
    let product_formulas =
      node.summaries
      |> List.concat_map (fun (pc : Abs.product_step_summary) ->
             Ir_formula.values (pc.requires @ pc.ensures)
             @
             let case_formulas =
               List.concat_map
                 (fun (case : Abs.safe_product_case) -> [ case.admissible_guard ])
                 pc.safe_cases
               @ List.concat_map
                   (fun (case : Abs.unsafe_product_case) -> [ case.excluded_guard ])
                   pc.unsafe_cases
             in
             Ir_formula.values case_formulas)
    in
    product_formulas @ Ir_formula.values node.init_invariant_goals
  in
  Collect.build_pre_k_infos_from_parts ~inputs:node.context.semantics.sem_inputs
    ~locals:node.context.semantics.sem_locals ~outputs:node.context.semantics.sem_outputs
    ~fo_formulas:summary_formulas
    ~ltl:(node.context.source_info.assumes @ node.context.source_info.guarantees)
    ~invariants_user:node.context.source_info.user_invariants
    ~invariants_state_rel:node.context.source_info.state_invariants

(** Build a [Ir_proof_views.raw_node] from a finalized abstract node.

    The node carries:
    - the executable transition body exported by the middle-end
    - the source assume/guarantee clauses kept in [source_info]

    No requires/ensures are copied — those are the responsibility of pass 4. *)
let build_raw_node ~(program_transitions : Abs.transition list) (node : Abs.node_ir) :
    Ir_proof_views.raw_node =
  let pre_k_map = compute_pre_k_map node in
  let transitions = List.map raw_transition_of_abs program_transitions in
  {
    core =
      {
        Ir_proof_views.node_name = node.context.semantics.sem_nname;
        inputs = node.context.semantics.sem_inputs;
        outputs = node.context.semantics.sem_outputs;
        locals = node.context.semantics.sem_locals;
        control_states = node.context.semantics.sem_states;
        init_state = node.context.semantics.sem_init_state;
      };
    pre_k_map;
    transitions;
    assumes = node.context.source_info.assumes;
    guarantees = node.context.source_info.guarantees;
  }

let apply_node (node : Abs.node_ir) : Abs.node_ir =
  let context = { node.context with pre_k_map = compute_pre_k_map node } in
  { node with context }

let apply_program (program : Abs.node_ir list) : Abs.node_ir list = List.map apply_node program
