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
open Core_syntax
type automaton_role =
  | Assume
  | Guarantee
[@@deriving yojson]

type reactive_transition_ir = {
  transition_id : string;
  src_state : ident;
  dst_state : ident;
  guard : Core_syntax.hexpr;
  guard_expr : expr option;
  requires : Ir.summary_formula list
      [@to_yojson Ir_json_codec.summary_formula_list_to_yojson]
      [@of_yojson Ir_json_codec.summary_formula_list_of_yojson];
  ensures : Ir.summary_formula list
      [@to_yojson Ir_json_codec.summary_formula_list_to_yojson]
      [@of_yojson Ir_json_codec.summary_formula_list_of_yojson];
  body_stmts : Ast.stmt list;
}
[@@deriving yojson]

type reactive_program_ir = {
  node_name : ident;
  init_state : ident;
  states : ident list;
  transitions : reactive_transition_ir list;
}
[@@deriving yojson]

type automaton_edge_ir = {
  src_index : int;
  dst_index : int;
  guard : Core_syntax.hexpr;
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
  prog_state : ident;
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
  program_transition : ident * ident;
  program_guard : Core_syntax.hexpr;
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
  | FactProgramState of ident
  | FactGuaranteeState of int
  | FactPhaseFormula of Core_syntax.hexpr
  | FactFormula of Core_syntax.hexpr
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
  | RelFactProgramState of ident
  | RelFactGuaranteeState of int
  | RelFactPhaseFormula of Core_syntax.hexpr
  | RelFactFormula of Core_syntax.hexpr
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
  node_name : ident;
  inputs : vdecl list;
  outputs : vdecl list;
  locals : vdecl list;
  states : ident list;
  init_state : ident;
}
[@@deriving yojson]

type proof_step_summary_ir = {
  steps : product_step_ir list;
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
  temporal_layout : (hexpr * Temporal_support.pre_k_info) list;
  historical_generated_clauses : generated_clause_ir list;
  eliminated_generated_clauses : generated_clause_ir list;
  symbolic_generated_clauses : relational_generated_clause_ir list;
  proof_step_summaries : proof_step_summary_ir list;
  ghost_locals : vdecl list;
}
[@@deriving yojson]

type exported_node_summary_ir = {
  signature : node_signature_ir;
  normalized_ir : node_ir;
  coherency_goals : Ir.summary_formula list
      [@to_yojson Ir_json_codec.summary_formula_list_to_yojson]
      [@of_yojson Ir_json_codec.summary_formula_list_of_yojson];
  temporal_layout : (hexpr * Temporal_support.pre_k_info) list;
  delay_spec : (ident * ident) option;
  assumes : ltl list;
  guarantees : ltl list;
}
[@@deriving yojson]
