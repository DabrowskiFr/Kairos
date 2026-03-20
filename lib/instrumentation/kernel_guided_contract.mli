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
  tick_summary : Product_kernel_ir.callee_tick_abi_ir option;
}

type obligation_layers = {
  historical : Product_kernel_ir.generated_clause_ir list;
  eliminated : Product_kernel_ir.generated_clause_ir list;
  symbolic : Product_kernel_ir.relational_generated_clause_ir list;
}

type symbolic_obligation_groups = {
  source_product_summaries : Product_kernel_ir.relational_generated_clause_ir list;
  phase_steps : Product_kernel_ir.relational_generated_clause_ir list;
  propagation : Product_kernel_ir.relational_generated_clause_ir list;
  safety : Product_kernel_ir.relational_generated_clause_ir list;
}

type node_contract = {
  node_name : Ast.ident;
  product_coverage : Product_kernel_ir.product_coverage_ir;
  obligations : obligation_layers;
  symbolic_groups : symbolic_obligation_groups;
  historical_clauses : Product_kernel_ir.generated_clause_ir list;
  eliminated_clauses : Product_kernel_ir.generated_clause_ir list;
  symbolic_clauses : Product_kernel_ir.relational_generated_clause_ir list;
  instance_relations : Product_kernel_ir.instance_relation_ir list;
  callee_tick_abis : Product_kernel_ir.callee_tick_abi_ir list;
}

val temporal_bindings_of_pre_k_map :
  (Ast.hexpr * Support.pre_k_info) list -> temporal_binding_ir list

val exported_summary_of_exported_ir :
  Product_kernel_ir.exported_node_summary_ir -> exported_summary_contract

val exported_summary_of_ast_node : Ast.node -> exported_summary_contract

val node_contract_of_ir : Product_kernel_ir.node_ir -> node_contract

val with_tick_summary :
  Product_kernel_ir.callee_tick_abi_ir option ->
  exported_summary_contract ->
  exported_summary_contract

val latest_slot_name_for_hexpr :
  exported_summary_contract -> Ast.hexpr -> Ast.ident option

val first_slot_name_for_input :
  exported_summary_contract -> Ast.ident -> Ast.ident option
