(** Clause generation and lowering for the kernel/product IR. *)

module Abs = Ir
module PT = Product_types

val build_generated_clauses :
  node:Abs.node ->
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
