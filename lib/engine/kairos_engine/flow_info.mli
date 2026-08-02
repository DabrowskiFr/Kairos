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

(** Runtime metadata produced by frontend and instrumentation stages. *)
open Core_syntax
(** {1 Per-pass Metadata} *)

(** Parser error payload. *)
type parse_error = { loc : Loc.loc option; message : string }

(** Parsing metadata reported by the frontend. *)
type parse_info = {
  source_path : string option;
  text_hash : string option;
  parse_errors : parse_error list;
  warnings : string list;
}

(** Metadata produced by the automata generation pass. *)
type automata_info = {
  (** States in the standard partial guarantee monitors returned by the
      producer. *)
  residual_state_count : int;
  (** Edges in those producer monitors. *)
  residual_edge_count : int;
  warnings : string list;
}

(** Metadata produced by the summaries pass. *)
type summaries_info = { warnings : string list }

(** Metadata produced after IR construction.

    This record only stores structural counters and pass warnings.
    Rendering and proof payloads are produced later by output modules. *)
type instrumentation_info = {
  (** Non-fatal warnings emitted while building proof artifacts. *)
  warnings : string list;
  (** Number of producer states in the partial assumption monitors. *)
  require_automata_state_count : int;
  (** Number of producer edges in the partial assumption monitors. *)
  require_automata_edge_count : int;
  (** Number of producer states in the partial guarantee monitors. *)
  ensures_automata_state_count : int;
  (** Number of producer edges in the partial guarantee monitors. *)
  ensures_automata_edge_count : int;
  (** Number of explicit product edges (sum over processed nodes). *)
  product_edge_count : int;
  (** Number of reachable product states (sum over processed nodes). *)
  product_state_count : int;
  (** Number of canonical summaries (sum over processed nodes). *)
  canonical_summary_count : int;
  (** Number of canonical product cases (sum over processed nodes). *)
  canonical_product_case_count : int;
}

type pipeline_info = {
  parse : parse_info option;
  automata_generation : automata_info option;
  summaries : summaries_info option;
  instrumentation : instrumentation_info option;
}
(** Technical metadata retained for CLI/LSP output projection. *)

(** Default empty parsing metadata. *)
val empty_parse_info : parse_info

(** Default empty automata-generation metadata. *)
val empty_automata_info : automata_info

(** Default empty summaries metadata. *)
val empty_summaries_info : summaries_info

(** Empty IR instrumentation metadata (all counters set to zero). *)
val empty_instrumentation_info : instrumentation_info
