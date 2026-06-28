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

(** Proof-kernel exchange data model.

    This module defines the proof-kernel exchange structures used for
    diagnostics and possible Rocq synchronization after an explicit adequacy
    decision. It owns product export records, relational/lowered clauses,
    proof-step summaries and exported node summaries.

    It does not own generated kernel clauses: [generated_clause_ir] is an alias
    for {!Kernel_clause_projection.classified_clause}. Serialization is
    provided here as a boundary codec, not as a second proof object. *)

open Core_syntax
(** Core type definitions for the product and proof-kernel IR.

    This module defines:
    {ul
    {- reactive-program fragments;}
    {- automata and product data;}
    {- generated kernel-clause projection aliases;}
    {- proof-step summaries;}
    {- exported node summaries.}} *)

type automaton_role =
  | Assume
  | Guarantee
[@@deriving yojson]

(** Reactive transition used by the kernel pipeline. *)
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
  body_stmts : Core_syntax.stmt list;
}
[@@deriving yojson]

(** Reactive program paired with kernel data. *)
type reactive_program_ir = {
  node_name : ident;
  init_state : ident;
  states : ident list;
  transitions : reactive_transition_ir list;
}
[@@deriving yojson]

(** Edge of an assumption or guarantee automaton used by the product. *)
type automaton_edge_ir = {
  src_index : int;
  dst_index : int;
  guard : Core_syntax.hexpr;
}
[@@deriving yojson]

(** Kernel-side view of a safety automaton. *)
type safety_automaton_ir = {
  role : automaton_role;
  initial_state_index : int;
  bad_state_index : int option;
  state_labels : (int * string) list;
  edges : automaton_edge_ir list;
}
[@@deriving yojson]

(** Explicit state of the semantic product program × assume × guarantee. *)
type product_state_ir = {
  prog_state : ident;
  assume_state_index : int;
  guarantee_state_index : int;
}
[@@deriving yojson]

(** Type [product_step_kind]. *)

type product_step_kind =
  | StepSafe
  | StepBadAssumption
  | StepBadGuarantee
[@@deriving yojson]

(** Type [product_step_origin]. *)

type product_step_origin =
  | StepFromExplicitExploration
[@@deriving yojson]

(** Transition of the semantic product.

    This is the canonical unit later used to derive proof-step summaries. *)
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

(** Type [product_coverage_ir]. *)

type product_coverage_ir =
  | CoverageEmpty
  | CoverageExplicit
[@@deriving yojson]

(** Time tag reused by lowered proof-export facts. The source of this
    vocabulary is {!Kernel_clause_projection}. *)
type clause_time_ir = Kernel_clause_projection.time_tag

val clause_time_ir_to_yojson : clause_time_ir -> Yojson.Safe.t
val clause_time_ir_of_yojson : Yojson.Safe.t -> (clause_time_ir, string) result

(** Clause produced before relational lowering. This is the neutral
    Rocq-facing kernel clause projection; proof_export must not define another
    generated-clause record. *)
type generated_clause_ir = Kernel_clause_projection.classified_clause

val generated_clause_ir_to_yojson : generated_clause_ir -> Yojson.Safe.t
val generated_clause_ir_of_yojson :
  Yojson.Safe.t -> (generated_clause_ir, string) result

(** Anchor of a lowered relational clause. *)
type relational_clause_anchor_ir = Kernel_clause_projection.clause_context

val relational_clause_anchor_ir_to_yojson :
  relational_clause_anchor_ir -> Yojson.Safe.t
val relational_clause_anchor_ir_of_yojson :
  Yojson.Safe.t -> (relational_clause_anchor_ir, string) result

(** Type [relational_clause_fact_desc_ir]. *)

type relational_clause_fact_desc_ir =
  | RelFactProgramState of ident
  | RelFactGuaranteeState of int
  | RelFactPhaseFormula of Core_syntax.hexpr
  | RelFactFormula of Core_syntax.hexpr
  | RelFactFalse
[@@deriving yojson]

(** Type [relational_clause_fact_ir]. *)

type relational_clause_fact_ir = {
  time : clause_time_ir;
  desc : relational_clause_fact_desc_ir;
}
[@@deriving yojson]

(** Clause after relational lowering. *)
type relational_generated_clause_ir = {
  family : Obligation_family_projection.clause_family
      [@to_yojson Ir_json_codec.clause_family_to_yojson]
      [@of_yojson Ir_json_codec.clause_family_of_yojson];
  anchor : relational_clause_anchor_ir;
  hypotheses : relational_clause_fact_ir list;
  conclusions : relational_clause_fact_ir list;
}
[@@deriving yojson]

(** Minimal exported signature for a node summary. *)
type node_signature_ir = {
  node_name : ident;
  inputs : vdecl list;
  outputs : vdecl list;
  locals : vdecl list;
  states : ident list;
  init_state : ident;
}
[@@deriving yojson]

(** Summary attached to one canonical proof-step group.

    Safe summaries may summarize several explicit product steps sharing the
    same program transition, source product state, and assume edge. Bad
    summaries remain singleton groups. *)
type proof_step_summary_ir = {
  steps : product_step_ir list;
  entry_clauses : relational_generated_clause_ir list;
  clauses : relational_generated_clause_ir list;
}
[@@deriving yojson]

(** Product and proof-kernel data for one node. *)
type node_ir = {
  reactive_program : reactive_program_ir;
  assume_automaton : safety_automaton_ir;
  guarantee_automaton : safety_automaton_ir;
  initial_product_state : product_state_ir;
  product_states : product_state_ir list;
  product_steps : product_step_ir list;
  product_coverage : product_coverage_ir;
  temporal_layout : Pre_k_layout.pre_k_info list;
  historical_generated_clauses : generated_clause_ir list;
  eliminated_generated_clauses : generated_clause_ir list;
  symbolic_generated_clauses : relational_generated_clause_ir list;
  proof_step_summaries : proof_step_summary_ir list;
  ghost_locals : vdecl list;
}
[@@deriving yojson]

(** Exported summary for one node. *)
type exported_node_summary_ir = {
  signature : node_signature_ir;
  normalized_ir : node_ir;
  coherency_goals : Ir.summary_formula list
      [@to_yojson Ir_json_codec.summary_formula_list_to_yojson]
      [@of_yojson Ir_json_codec.summary_formula_list_of_yojson];
  temporal_layout : Pre_k_layout.pre_k_info list;
  delay_spec : (ident * ident) option;
  assumes : ltl list;
  guarantees : ltl list;
}
[@@deriving yojson]
