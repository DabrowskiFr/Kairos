type automaton_role =
  | Assume
  | Guarantee

type reactive_transition_ir = {
  src_state : Ast.ident;
  dst_state : Ast.ident;
  guard : Ast.fo;
}

type reactive_program_ir = {
  node_name : Ast.ident;
  init_state : Ast.ident;
  states : Ast.ident list;
  transitions : reactive_transition_ir list;
}

type automaton_edge_ir = {
  src_index : int;
  dst_index : int;
  guard : Ast.fo;
}

type safety_automaton_ir = {
  role : automaton_role;
  initial_state_index : int;
  bad_state_index : int option;
  state_labels : (int * string) list;
  edges : automaton_edge_ir list;
}

type product_state_ir = {
  prog_state : Ast.ident;
  assume_state_index : int;
  guarantee_state_index : int;
}

type product_step_kind =
  | StepSafe
  | StepBadAssumption
  | StepBadGuarantee

type product_step_origin =
  | StepFromExplicitExploration
  | StepFromFallbackSynthesis

type product_step_ir = {
  src : product_state_ir;
  dst : product_state_ir;
  program_transition : Ast.ident * Ast.ident;
  program_guard : Ast.fo;
  assume_edge : automaton_edge_ir;
  guarantee_edge : automaton_edge_ir;
  step_kind : product_step_kind;
  step_origin : product_step_origin;
}

type product_coverage_ir =
  | CoverageEmpty
  | CoverageExplicit
  | CoverageFallback

type generated_clause_origin =
  | OriginSafety
  | OriginInitNodeInvariant
  | OriginInitAutomatonCoherence
  | OriginPropagationNodeInvariant
  | OriginPropagationAutomatonCoherence

type clause_time_ir =
  | CurrentTick
  | PreviousTick

type clause_fact_desc_ir =
  | FactProgramState of Ast.ident
  | FactGuaranteeState of int
  | FactFormula of Ast.fo
  | FactFalse

type clause_fact_ir = {
  time : clause_time_ir;
  desc : clause_fact_desc_ir;
}

type generated_clause_anchor_ir =
  | ClauseAnchorProductState of product_state_ir
  | ClauseAnchorProductStep of product_step_ir

type generated_clause_ir = {
  origin : generated_clause_origin;
  anchor : generated_clause_anchor_ir;
  hypotheses : clause_fact_ir list;
  conclusions : clause_fact_ir list;
}

type instance_relation_ir =
  | InstanceUserInvariant of {
      instance_name : Ast.ident;
      callee_node_name : Ast.ident;
      invariant_id : Ast.ident;
      invariant_expr : Ast.hexpr;
    }
  | InstanceStateInvariant of {
      instance_name : Ast.ident;
      callee_node_name : Ast.ident;
      state_name : Ast.ident;
      is_eq : bool;
      formula : Ast.fo;
    }
  | InstanceDelayHistoryLink of {
      instance_name : Ast.ident;
      callee_node_name : Ast.ident;
      caller_output : Ast.ident;
      callee_input : Ast.ident;
      callee_pre_name : Ast.ident option;
    }
  | InstanceDelayCallerPreLink of {
      caller_output : Ast.ident;
      caller_pre_name : Ast.ident;
    }

type call_port_role =
  | CallInputPort
  | CallOutputPort
  | CallStatePort

type call_port_ir = {
  port_name : Ast.ident;
  role : call_port_role;
}

type call_binding_kind =
  | BindActualInput
  | BindActualOutput
  | BindInstancePreState
  | BindInstancePostState

type call_binding_ir = {
  binding_kind : call_binding_kind;
  local_name : Ast.ident;
  remote_name : Ast.ident;
}

type call_fact_kind =
  | CallEntryFact
  | CallTransitionFact
  | CallExportedPostFact

type call_fact_ir = {
  fact_kind : call_fact_kind;
  fact : clause_fact_ir;
}

type callee_summary_case_ir = {
  case_name : string;
  entry_facts : call_fact_ir list;
  transition_facts : call_fact_ir list;
  exported_post_facts : call_fact_ir list;
}

type callee_tick_abi_ir = {
  callee_node_name : Ast.ident;
  input_ports : call_port_ir list;
  output_ports : call_port_ir list;
  state_ports : call_port_ir list;
  cases : callee_summary_case_ir list;
}

type call_site_instantiation_ir = {
  instance_name : Ast.ident;
  call_site_id : string;
  callee_node_name : Ast.ident;
  bindings : call_binding_ir list;
}

type node_ir = {
  reactive_program : reactive_program_ir;
  assume_automaton : safety_automaton_ir;
  guarantee_automaton : safety_automaton_ir;
  initial_product_state : product_state_ir;
  product_states : product_state_ir list;
  product_steps : product_step_ir list;
  product_coverage : product_coverage_ir;
  generated_clauses : generated_clause_ir list;
  instance_relations : instance_relation_ir list;
  callee_tick_abis : callee_tick_abi_ir list;
  call_site_instantiations : call_site_instantiation_ir list;
}

val has_effective_product_coverage : node_ir -> bool

val of_node_analysis :
  node_name:Ast.ident ->
  nodes:Abstract_model.node list ->
  node:Abstract_model.node ->
  analysis:Product_build.analysis ->
  node_ir

val render_call_summary_toy_example : string list

val render_node_ir : node_ir -> string list
