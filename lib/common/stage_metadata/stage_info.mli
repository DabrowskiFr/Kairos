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
type contracts_info = {
  contract_origin_map : (int * Formula_origin.t option) list;
  warnings : string list;
}

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
  (** Pass 3 output: raw IR nodes (no Hoare triples). *)
  raw_ir_nodes : Ir.raw_node list;
  (** Pass 4 output: annotated IR nodes (Hoare triples added, pre_k references still present). *)
  annotated_ir_nodes : Ir.annotated_node list;
  (** Pass 5 output: verified IR nodes (history eliminated, ready for Why3). *)
  verified_ir_nodes : Ir.verified_node list;
  (** Text rendering of the kernel IR. *)
  kernel_pipeline_lines : string list;
  (** Non-fatal warnings emitted while building proof artifacts. *)
  warnings : string list;
  (** Text rendering of the guarantee automaton. *)
  guarantee_automaton_lines : string list;
  (** Text rendering of the assume automaton. *)
  assume_automaton_lines : string list;
  (** LaTeX rendering of the guarantee automaton guards. *)
  guarantee_automaton_tex : string;
  (** LaTeX rendering of the assume automaton guards. *)
  assume_automaton_tex : string;
  (** LaTeX rendering of the product-transition guards. *)
  product_tex : string;
  (** LaTeX rendering of the explicit product-transition guards. *)
  product_tex_explicit : string;
  (** LaTeX rendering of the canonical proof-step structure. *)
  canonical_tex : string;
  (** Text rendering of the explored product. *)
  product_lines : string list;
  (** Text rendering of the canonical proof-step structure. *)
  canonical_lines : string list;
  (** Text rendering of generated obligations. *)
  obligations_lines : string list;
  (** DOT rendering of the guarantee automaton. *)
  guarantee_automaton_dot : string;
  (** DOT rendering of the assume automaton. *)
  assume_automaton_dot : string;
  (** DOT rendering of the product graph. *)
  product_dot : string;
  (** DOT rendering of the explicit product graph. *)
  product_dot_explicit : string;
  (** DOT rendering of the canonical proof-step structure. *)
  canonical_dot : string;
}

(** Default empty parsing metadata. *)
val empty_parse_info : parse_info

(** Default empty automata-generation metadata. *)
val empty_automata_info : automata_info

(** Default empty contracts metadata. *)
val empty_contracts_info : contracts_info

(** Empty proof-artifact metadata.

    Every list field is empty and every DOT payload is the empty string. *)
val empty_instrumentation_info : instrumentation_info
