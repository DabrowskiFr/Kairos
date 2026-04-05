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

(** Clause generation and lowering for the kernel/product IR. *)

module Abs = Ir
module PT = Product_types

val build_generated_clauses :
  node:Abs.node_ir ->
  analysis:Product_build.analysis ->
  initial_state:Proof_kernel_types.product_state_ir ->
  steps:Proof_kernel_types.product_step_ir list ->
  automaton_guard_fo:((Ast.ident * Ast.iexpr) list ->
    Automaton_types.guard ->
    Fo_formula.t) ->
  is_live_state:(analysis:Product_build.analysis -> PT.product_state -> bool) ->
  Proof_kernel_types.generated_clause_ir list

val lower_clause_fact :
  pre_k_map:(Ast.hexpr * Temporal_support.pre_k_info) list ->
  Proof_kernel_types.clause_fact_ir ->
  Proof_kernel_types.clause_fact_ir option

val lower_generated_clause :
  pre_k_map:(Ast.hexpr * Temporal_support.pre_k_info) list ->
  Proof_kernel_types.generated_clause_ir ->
  Proof_kernel_types.generated_clause_ir option

val relationalize_clause_fact :
  pre_k_map:(Ast.hexpr * Temporal_support.pre_k_info) list ->
  Proof_kernel_types.clause_fact_ir ->
  Proof_kernel_types.relational_clause_fact_ir option

val expand_relational_hypotheses :
  Proof_kernel_types.relational_clause_fact_ir list ->
  Proof_kernel_types.relational_clause_fact_ir list list

val normalize_relational_hypotheses :
  Proof_kernel_types.relational_clause_fact_ir list ->
  Proof_kernel_types.relational_clause_fact_ir list option

val relationalize_generated_clause :
  pre_k_map:(Ast.hexpr * Temporal_support.pre_k_info) list ->
  Proof_kernel_types.generated_clause_ir ->
  Proof_kernel_types.relational_generated_clause_ir list
