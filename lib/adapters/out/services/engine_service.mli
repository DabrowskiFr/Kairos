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

(** Unified engine selector used by CLI, LSP, and IDE.

    The current implementation exposes a single concrete engine ([Default]),
    while keeping an explicit selection API for future backends.
*)

type engine = Default

(** Parse a textual engine name. *)

val engine_of_string : string -> engine option
(** Canonical string representation of an engine value. *)

val string_of_engine : engine -> string
(** Normalize aliases to canonical engine variants. *)

val normalize : engine -> engine
(** Human-readable rendering for pipeline errors. *)

val error_to_string : Pipeline_types.error -> string

(** Engine-dispatched instrumentation/artifacts pass. *)

val instrumentation_pass :
  engine:engine -> generate_png:bool -> input_file:string ->
  (Pipeline_types.automata_outputs, Pipeline_types.error) result

(** Engine-dispatched Why text generation pass. *)

val why_pass :
  engine:engine ->
  input_file:string ->
  (Pipeline_types.why_outputs, Pipeline_types.error) result

(** Engine-dispatched VC/SMT obligations generation pass. *)

val obligations_pass :
  engine:engine ->
  input_file:string ->
  (Pipeline_types.obligations_outputs, Pipeline_types.error) result

(** Render textual summary for a [.kobj] file or source program. *)

val kobj_summary :
  engine:engine -> input_file:string -> (string, Pipeline_types.error) result

(** Render exported kernel clauses for a [.kobj] file or source program. *)

val kobj_clauses :
  engine:engine -> input_file:string -> (string, Pipeline_types.error) result

(** Render exported product view for a [.kobj] file or source program. *)

val kobj_product :
  engine:engine -> input_file:string -> (string, Pipeline_types.error) result

(** Render exported summaries view for a [.kobj] file or source program. *)

val kobj_contracts :
  engine:engine -> input_file:string -> (string, Pipeline_types.error) result

(** Render normalized IR text for [input_file]. *)

val normalized_program :
  engine:engine -> input_file:string -> (string, Pipeline_types.error) result
(** Render pretty IR text for [input_file]. *)

val ir_pretty_dump :
  engine:engine -> input_file:string -> (string, Pipeline_types.error) result

(** Execute the full pipeline using [engine]. *)

val run :
  engine:engine -> Pipeline_types.config ->
  (Pipeline_types.outputs, Pipeline_types.error) result

(** Execute the full pipeline from raw flag arguments.

    This helper preserves the historical API shape used by some callers.
*)

val run_raw :
  engine:engine ->
  input_file:string ->
  wp_only:bool ->
  smoke_tests:bool ->
  timeout_s:int ->
  compute_proof_diagnostics:bool ->
  prove:bool ->
  generate_vc_text:bool ->
  generate_smt_text:bool ->
  generate_dot_png:bool ->
  (Pipeline_types.outputs, Pipeline_types.error) result

(** Execute the full pipeline with streaming callbacks. *)

val run_with_callbacks :
  engine:engine ->
  should_cancel:(unit -> bool) ->
  Pipeline_types.config ->
  on_outputs_ready:(Pipeline_types.outputs -> unit) ->
  on_goals_ready:(string list * int list -> unit) ->
  on_goal_done:(int -> string -> string -> float -> string option -> string option -> unit) ->
  (Pipeline_types.outputs, Pipeline_types.error) result
