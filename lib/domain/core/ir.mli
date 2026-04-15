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


(** Canonical IR types used between middle-end passes and backends.

    This module defines:
    - logical formulas with metadata;
    - product/summaries structures used by local-proof generation;
    - node/program IR containers consumed by later pipeline phases. *)

open Ir_shared_types
open Core_syntax

(** Metadata attached to one logical formula in the IR. *)
type formula_meta = {
  oid : formula_id;
  loc : Loc.loc option;
}

(** Formula used in IR summaries and goals. *)
type summary_formula = {
  logic : Core_syntax.hexpr;
  meta : formula_meta;
}

(** Materialized temporal history layout used after canonical IR construction. *)
type temporal_layout = Pre_k_layout.pre_k_info list

(** Product state: (program control, assume automaton, guarantee automaton). *)
type product_state = {
  prog_state : ident;
  assume_state_index : automaton_state_index;
  guarantee_state_index : automaton_state_index;
}

(** Normalized executable transition used by the IR summaries. *)
type transition = {
  src_state : ident;
  dst_state : ident;
  guard_expr : expr option;
  body_stmts : stmt list;
}


(** Admissible branch: destination product state + admissibility guard. *)
type safe_product_case = {
  product_dst : product_state;
  admissible_guard : summary_formula;
}

(** Excluded branch: destination product state + guard to forbid. *)
type unsafe_product_case = {
  product_dst : product_state;
  excluded_guard : summary_formula;
}

(** Traceability metadata for one local summary. *)
type product_step_summary_trace = { step_uid : transition_index }

(** Grouping key for one local product-step summary. *)
type product_step_summary_identity = {
  program_step : transition;
  product_src : product_state;
  assume_guard : Core_syntax.hexpr;
}

(** Local summary of grouped product steps. *)
type product_step_summary = {
  trace : product_step_summary_trace;
  identity : product_step_summary_identity;
  propagation_requires : summary_formula list;
  requires : summary_formula list;
  ensures : summary_formula list;
  safe_cases : safe_product_case list;
  unsafe_cases : unsafe_product_case list;
}

(** Core node signature required by the canonical IR. *)
type node_signature = {
  sem_nname : ident;
  sem_inputs : vdecl list;
  sem_outputs : vdecl list;
  sem_locals : vdecl list;
  sem_states : ident list;
  sem_init_state : ident;
}

(** State invariant already converted to FO (non-temporal by construction). *)
type state_invariant = {
  state : ident;
  formula : Core_syntax.hexpr;
}

(** Source-level specs and invariants kept for traceability/export. *)
type source_info = {
  assumes : ltl list;
  guarantees : ltl list;
  state_invariants : state_invariant list;
}

(** Full canonical IR for one node. *)
type node_ir = {
  semantics : node_signature;
  source_info : source_info;
  temporal_layout : temporal_layout;
  summaries : product_step_summary list;
  init_invariant_goals : summary_formula list;
}

(** Canonical IR for a whole program. *)
type program_ir = { nodes : node_ir list }
