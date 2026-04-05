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

(** Grouped contract view extracted from kernel IR for Why generation and
    summary export. *)

type temporal_binding_ir = {
  source_hexpr : Ast.hexpr;
  source_expr : Ast.iexpr;
  slot_names : Ast.ident list;
}

type exported_summary_contract = {
  callee_node_name : Ast.ident;
  input_names : Ast.ident list;
  output_names : Ast.ident list;
  user_invariants : Ast.invariant_user list;
  state_invariants : Ast.invariant_state_rel list;
  temporal_bindings : temporal_binding_ir list;
}

type obligation_layers = {
  historical : Proof_kernel_types.generated_clause_ir list;
  eliminated : Proof_kernel_types.generated_clause_ir list;
  symbolic : Proof_kernel_types.relational_generated_clause_ir list;
}

type symbolic_obligation_groups = {
  source_product_summaries : Proof_kernel_types.relational_generated_clause_ir list;
  phase_steps : Proof_kernel_types.relational_generated_clause_ir list;
  propagation : Proof_kernel_types.relational_generated_clause_ir list;
  safety : Proof_kernel_types.relational_generated_clause_ir list;
}

type node_contract = {
  node_name : Ast.ident;
  product_coverage : Proof_kernel_types.product_coverage_ir;
  obligations : obligation_layers;
  symbolic_groups : symbolic_obligation_groups;
  proof_step_contracts : Proof_kernel_types.proof_step_contract_ir list;
  historical_clauses : Proof_kernel_types.generated_clause_ir list;
  eliminated_clauses : Proof_kernel_types.generated_clause_ir list;
  symbolic_clauses : Proof_kernel_types.relational_generated_clause_ir list;
}

val temporal_bindings_of_pre_k_map :
  (Ast.hexpr * Temporal_support.pre_k_info) list -> temporal_binding_ir list

val exported_summary_of_exported_ir :
  Proof_kernel_types.exported_node_summary_ir -> exported_summary_contract

val exported_summary_of_ast_node : Ast.node -> exported_summary_contract

val node_contract_of_ir : Proof_kernel_types.node_ir -> node_contract

val latest_slot_name_for_hexpr :
  exported_summary_contract -> Ast.hexpr -> Ast.ident option

val first_slot_name_for_input :
  exported_summary_contract -> Ast.ident -> Ast.ident option
