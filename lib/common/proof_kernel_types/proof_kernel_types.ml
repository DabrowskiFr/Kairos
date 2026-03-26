type automaton_role =
  | Assume
  | Guarantee
[@@deriving yojson]

type reactive_transition_ir = {
  transition_id : string;
  src_state : Ast.ident;
  dst_state : Ast.ident;
  guard : Fo_formula.t;
  guard_iexpr : Ast.iexpr option;
  requires : Ir.contract_formula list;
  ensures : Ir.contract_formula list;
  body_stmts : Ast.stmt list;
}
[@@deriving yojson]

type reactive_program_ir = {
  node_name : Ast.ident;
  init_state : Ast.ident;
  states : Ast.ident list;
  transitions : reactive_transition_ir list;
}
[@@deriving yojson]

type automaton_edge_ir = {
  src_index : int;
  dst_index : int;
  guard : Fo_formula.t;
}
[@@deriving yojson]

type safety_automaton_ir = {
  role : automaton_role;
  initial_state_index : int;
  bad_state_index : int option;
  state_labels : (int * string) list;
  edges : automaton_edge_ir list;
}
[@@deriving yojson]

type product_state_ir = {
  prog_state : Ast.ident;
  assume_state_index : int;
  guarantee_state_index : int;
}
[@@deriving yojson]

type product_step_kind =
  | StepSafe
  | StepBadAssumption
  | StepBadGuarantee
[@@deriving yojson]

type product_step_origin =
  | StepFromExplicitExploration
  | StepFromFallbackSynthesis
[@@deriving yojson]

type product_step_ir = {
  src : product_state_ir;
  dst : product_state_ir;
  program_transition_id : string;
  program_transition : Ast.ident * Ast.ident;
  program_guard : Fo_formula.t;
  assume_edge : automaton_edge_ir;
  guarantee_edge : automaton_edge_ir;
  step_kind : product_step_kind;
  step_origin : product_step_origin;
}
[@@deriving yojson]

type product_coverage_ir =
  | CoverageEmpty
  | CoverageExplicit
  | CoverageFallback
[@@deriving yojson]

type generated_clause_origin =
  | OriginSourceProductSummary
  | OriginPhaseStepPreSummary
  | OriginPhaseStepSummary
  | OriginSafety
  | OriginInitNodeInvariant
  | OriginInitAutomatonCoherence
  | OriginPropagationNodeInvariant
  | OriginPropagationAutomatonCoherence
[@@deriving yojson]

type clause_time_ir =
  | CurrentTick
  | PreviousTick
  | StepTickContext
[@@deriving yojson]

type clause_fact_desc_ir =
  | FactProgramState of Ast.ident
  | FactGuaranteeState of int
  | FactPhaseFormula of Ast.ltl
  | FactFormula of Ast.ltl
  | FactFalse
[@@deriving yojson]

type clause_fact_ir = {
  time : clause_time_ir;
  desc : clause_fact_desc_ir;
}
[@@deriving yojson]

type generated_clause_anchor_ir =
  | ClauseAnchorProductState of product_state_ir
  | ClauseAnchorProductStep of product_step_ir
[@@deriving yojson]

type generated_clause_ir = {
  origin : generated_clause_origin;
  anchor : generated_clause_anchor_ir;
  hypotheses : clause_fact_ir list;
  conclusions : clause_fact_ir list;
}
[@@deriving yojson]

type relational_clause_fact_desc_ir =
  | RelFactProgramState of Ast.ident
  | RelFactGuaranteeState of int
  | RelFactPhaseFormula of Ast.ltl
  | RelFactFormula of Ast.ltl
  | RelFactFalse
[@@deriving yojson]

type relational_clause_fact_ir = {
  time : clause_time_ir;
  desc : relational_clause_fact_desc_ir;
}
[@@deriving yojson]

type relational_generated_clause_ir = {
  origin : generated_clause_origin;
  anchor : generated_clause_anchor_ir;
  hypotheses : relational_clause_fact_ir list;
  conclusions : relational_clause_fact_ir list;
}
[@@deriving yojson]

type node_signature_ir = {
  node_name : Ast.ident;
  inputs : Ast.vdecl list;
  outputs : Ast.vdecl list;
  locals : Ast.vdecl list;
  instances : (Ast.ident * Ast.ident) list;
  states : Ast.ident list;
  init_state : Ast.ident;
}
[@@deriving yojson]

type proof_step_contract_ir = {
  step : product_step_ir;
  entry_clauses : relational_generated_clause_ir list;
  clauses : relational_generated_clause_ir list;
}
[@@deriving yojson]

type node_ir = {
  reactive_program : reactive_program_ir;
  assume_automaton : safety_automaton_ir;
  guarantee_automaton : safety_automaton_ir;
  initial_product_state : product_state_ir;
  product_states : product_state_ir list;
  product_steps : product_step_ir list;
  product_coverage : product_coverage_ir;
  historical_generated_clauses : generated_clause_ir list;
  eliminated_generated_clauses : generated_clause_ir list;
  symbolic_generated_clauses : relational_generated_clause_ir list;
  proof_step_contracts : proof_step_contract_ir list;
  ghost_locals : Ast.vdecl list;
}
[@@deriving yojson]

type exported_node_summary_ir = {
  signature : node_signature_ir;
  normalized_ir : node_ir;
  user_invariants : Ast.invariant_user list;
  coherency_goals : Ir.contract_formula list;
  pre_k_map : (Ast.hexpr * Temporal_support.pre_k_info) list;
  delay_spec : (Ast.ident * Ast.ident) option;
  assumes : Ast.ltl list;
  guarantees : Ast.ltl list;
}
[@@deriving yojson]
