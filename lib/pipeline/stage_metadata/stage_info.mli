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

(** Bundles the intermediate artifacts produced by instrumentation stages. *)

(** {1 Per-pass Metadata} *)

(** Parser error payload. *)
type parse_error = { loc : Ast.loc option; message : string }

(** Parsing metadata reported by the frontend. *)
type parse_info = {
  source_path : string option;
  text_hash : string option;
  parse_errors : parse_error list;
  warnings : string list;
}

(** Metadata produced by the automata generation pass. *)
type automata_info = {
  residual_state_count : int;
  residual_edge_count : int;
  warnings : string list;
}

(** Metadata produced by the contracts pass. *)
type formulas_info = { warnings : string list }

(** Metadata produced after IR construction and proof-artifact export.

    The record groups:
    {ul
    {- structured IR outputs;}
    {- exported kernel summaries;}
    {- human-readable renderings for diagnostics;}
    {- DOT renderings for automata and product views;}
    {- warnings emitted during this export stage.}} *)
type instrumentation_info = {
  (** Kernel-style IR for each processed node. *)
  kernel_ir_nodes : Proof_kernel_types.node_ir list;
  (** Export-oriented node summaries paired with the kernel IR. *)
  exported_node_summaries : Proof_kernel_types.exported_node_summary_ir list;
  (** Text rendering of the kernel IR. *)
  kernel_pipeline_lines : string list;
  (** Non-fatal warnings emitted while building proof artifacts. *)
  warnings : string list;
  (** Text rendering of the guarantee automaton. *)
  guarantee_automaton_lines : string list;
  (** Text rendering of the assume automaton. *)
  assume_automaton_lines : string list;
  (** Text rendering of the canonical proof-step structure. *)
  canonical_lines : string list;
  (** DOT rendering of the guarantee automaton. *)
  guarantee_automaton_dot : string;
  (** DOT rendering of the assume automaton. *)
  assume_automaton_dot : string;
  (** DOT rendering of the product graph. *)
  product_dot : string;
  (** DOT rendering of the canonical proof-step structure. *)
  canonical_dot : string;
  (** Number of states in the require automata (sum over processed nodes). *)
  require_automata_state_count : int;
  (** Number of edges in the require automata (sum over processed nodes). *)
  require_automata_edge_count : int;
  (** Number of states in the ensures automata (sum over processed nodes). *)
  ensures_automata_state_count : int;
  (** Number of edges in the ensures automata (sum over processed nodes). *)
  ensures_automata_edge_count : int;
  (** Number of edges in the full explicit product (sum over processed nodes). *)
  product_edge_count_full : int;
  (** Number of edges in the live product subgraph:
      excludes steps whose source is in [G_bad] or whose destination is in [A_bad]. *)
  product_edge_count_live : int;
  (** Number of product states in the full explicit product (sum over processed nodes). *)
  product_state_count_full : int;
  (** Number of product states in the classical live subgraph
      (states that are neither [A_bad] nor [G_bad]). *)
  product_state_count_live : int;
  (** Number of canonical contracts (sum over processed nodes). *)
  canonical_summary_count : int;
  (** Number of safe canonical cases (sum over processed nodes). *)
  canonical_case_safe_count : int;
  (** Number of bad-assumption canonical cases (sum over processed nodes). *)
  canonical_case_bad_assumption_count : int;
  (** Number of bad-guarantee canonical cases (sum over processed nodes). *)
  canonical_case_bad_guarantee_count : int;
}

(** Default empty parsing metadata. *)
val empty_parse_info : parse_info

(** Default empty automata-generation metadata. *)
val empty_automata_info : automata_info

(** Default empty contracts metadata. *)
val empty_contracts_info : formulas_info

(** Empty proof-artifact metadata.

    Every list field is empty and every DOT payload is the empty string. *)
val empty_instrumentation_info : instrumentation_info
