(** Call-summary, ABI, and instance-relation logic for the kernel/product IR. *)

module Abs = Normalized_program

val callee_tick_abi_of_node : node:Abs.node -> Proof_kernel_types.callee_tick_abi_ir

val lower_callee_tick_abi :
  pre_k_map:(Ast.hexpr * Support.pre_k_info) list ->
  lower_clause_fact:(pre_k_map:(Ast.hexpr * Support.pre_k_info) list ->
    Proof_kernel_types.clause_fact_ir ->
    Proof_kernel_types.clause_fact_ir option) ->
  Proof_kernel_types.callee_tick_abi_ir ->
  Proof_kernel_types.callee_tick_abi_ir

val build_proof_step_contracts :
  product_steps:Proof_kernel_types.product_step_ir list ->
  pre_k_map:(Ast.hexpr * Support.pre_k_info) list ->
  initial_product_state:Proof_kernel_types.product_state_ir ->
  symbolic_generated_clauses:Proof_kernel_types.relational_generated_clause_ir list ->
  Proof_kernel_types.proof_step_contract_ir list

val build_call_site_instantiations :
  nodes:Abs.node list ->
  external_summaries:Proof_kernel_types.exported_node_summary_ir list ->
  node:Abs.node ->
  node_signature_of_ast:(Ast.node -> Proof_kernel_types.node_signature_ir) ->
  build_pre_k_infos:(Ast.node -> (Ast.hexpr * Support.pre_k_info) list) ->
  extract_delay_spec:(Ast.ltl list -> (Ast.ident * Ast.ident) option) ->
  of_node_analysis:(node_name:Ast.ident ->
    nodes:Abs.node list ->
    external_summaries:Proof_kernel_types.exported_node_summary_ir list ->
    node:Abs.node ->
    analysis:Product_build.analysis ->
    Proof_kernel_types.node_ir) ->
  Proof_kernel_types.call_site_instantiation_ir list

val build_instance_relations :
  nodes:Abs.node list ->
  external_summaries:Proof_kernel_types.exported_node_summary_ir list ->
  node:Abs.node ->
  node_signature_of_ast:(Ast.node -> Proof_kernel_types.node_signature_ir) ->
  build_pre_k_infos:(Ast.node -> (Ast.hexpr * Support.pre_k_info) list) ->
  extract_delay_spec:(Ast.ltl list -> (Ast.ident * Ast.ident) option) ->
  of_node_analysis:(node_name:Ast.ident ->
    nodes:Abs.node list ->
    external_summaries:Proof_kernel_types.exported_node_summary_ir list ->
    node:Abs.node ->
    analysis:Product_build.analysis ->
    Proof_kernel_types.node_ir) ->
  Proof_kernel_types.instance_relation_ir list
