open Ast

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

let temporal_bindings_of_pre_k_map (pre_k_map : (Ast.hexpr * Support.pre_k_info) list) :
    temporal_binding_ir list =
  List.map
    (fun (source_hexpr, (info : Support.pre_k_info)) ->
      let slot_names =
        match source_hexpr with
        | HPreK (_, k) when k > 0 && k <= List.length info.names -> [ List.nth info.names (k - 1) ]
        | HPreK _ -> []
        | HNow _ -> info.names
      in
      { source_hexpr; source_expr = info.expr; slot_names })
    pre_k_map

let exported_summary_of_exported_ir
    (summary : Product_kernel_ir.exported_node_summary_ir) : exported_summary_contract =
  {
    callee_node_name = summary.signature.node_name;
    input_names = List.map (fun (v : Ast.vdecl) -> v.vname) summary.signature.inputs;
    output_names = List.map (fun (v : Ast.vdecl) -> v.vname) summary.signature.outputs;
    user_invariants = summary.user_invariants;
    state_invariants = summary.state_invariants;
    temporal_bindings = temporal_bindings_of_pre_k_map summary.pre_k_map;
    tick_summary = Some summary.tick_summary;
  }

let exported_summary_of_ast_node (node : Ast.node) : exported_summary_contract =
  {
    callee_node_name = node.semantics.sem_nname;
    input_names = Ast_utils.input_names_of_node node;
    output_names = Ast_utils.output_names_of_node node;
    user_invariants = node.attrs.invariants_user;
    state_invariants = node.specification.spec_invariants_state_rel;
    temporal_bindings = temporal_bindings_of_pre_k_map (Collect.build_pre_k_infos node);
    tick_summary = None;
  }

let node_contract_of_ir (ir : Product_kernel_ir.node_ir) : node_contract =
  let obligations =
    {
      historical = ir.historical_generated_clauses;
      eliminated = ir.eliminated_generated_clauses;
      symbolic = ir.symbolic_generated_clauses;
    }
  in
  let symbolic_groups =
    {
      source_product_summaries =
        List.filter
          (fun clause -> clause.Product_kernel_ir.origin = Product_kernel_ir.OriginSourceProductSummary)
          obligations.symbolic;
      phase_steps =
        List.filter
          (fun clause -> clause.Product_kernel_ir.origin = Product_kernel_ir.OriginPhaseStepSummary)
          obligations.symbolic;
      propagation =
        List.filter
          (fun clause ->
            clause.Product_kernel_ir.origin = Product_kernel_ir.OriginPropagationNodeInvariant
            || clause.Product_kernel_ir.origin = Product_kernel_ir.OriginPropagationAutomatonCoherence)
          obligations.symbolic;
      safety =
        List.filter
          (fun clause -> clause.Product_kernel_ir.origin = Product_kernel_ir.OriginSafety)
          obligations.symbolic;
    }
  in
  {
    node_name = ir.reactive_program.node_name;
    product_coverage = ir.product_coverage;
    obligations;
    symbolic_groups;
    historical_clauses = obligations.historical;
    eliminated_clauses = obligations.eliminated;
    symbolic_clauses = obligations.symbolic;
    instance_relations = ir.instance_relations;
    callee_tick_abis = ir.callee_tick_abis;
  }

let with_tick_summary
    (tick_summary : Product_kernel_ir.callee_tick_abi_ir option)
    (summary : exported_summary_contract) : exported_summary_contract =
  { summary with tick_summary }

let latest_slot_name_for_hexpr (summary : exported_summary_contract) (h : Ast.hexpr) :
    Ast.ident option =
  summary.temporal_bindings
  |> List.find_map (fun binding ->
         if binding.source_hexpr = h then
           match List.rev binding.slot_names with
           | name :: _ -> Some name
           | [] -> None
         else None)

let first_slot_name_for_input (summary : exported_summary_contract) (input_name : Ast.ident) :
    Ast.ident option =
  summary.temporal_bindings
  |> List.find_map (fun binding ->
         match (binding.source_expr.iexpr, binding.slot_names) with
         | IVar x, first :: _ when x = input_name -> Some first
         | _ -> None)
