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

(** High-level pipeline service used by entrypoints.

    This façade exposes both structured pipeline APIs and convenience dump APIs
    consumed by CLI/LSP commands.
*)

type goal_info = string * string * float * string option * string option
(** Stage metadata emitted by the pipeline ([section -> key/value pairs]). *)

type flow_meta = (string * (string * string) list) list

(** Aggregated textual and DOT dumps for automata/product/canonical views. *)

type automata_dump_data = {
  guarantee_automaton_text : string;
  assume_automaton_text : string;
  guarantee_automaton_dot : string;
  assume_automaton_dot : string;
  product_text : string;
  product_dot : string;
  canonical_text : string;
  canonical_dot : string;
  obligations_map_text : string;
}

(** Obligations dump payload (VC text and SMT text). *)

type obligations_dump_data = {
  vc_text : string;
  smt_text : string;
}

(** Full dump payload produced by [run_dump_data]. *)

type run_dump_data = {
  why_text : string;
  vc_text : string;
  smt_text : string;
  flow_meta : flow_meta;
  goals : goal_info list;
}

(** Run instrumentation/artifacts pass on [input_file]. *)

val instrumentation_pass :
  generate_png:bool ->
  input_file:string ->
  (Pipeline_types.automata_outputs, Pipeline_types.error) result

(** Generate Why text outputs for [input_file]. *)

val why_pass :
  input_file:string ->
  (Pipeline_types.why_outputs, Pipeline_types.error) result

(** Generate VC/SMT obligations for [input_file]. *)

val obligations_pass :
  input_file:string ->
  (Pipeline_types.obligations_outputs, Pipeline_types.error) result

(** Build unified automata/product/canonical dumps for [input_file]. *)

val automata_dump_data :
  input_file:string -> (automata_dump_data, Pipeline_types.error) result

(** Return Why text dump only. *)

val why_text_dump :
  input_file:string -> (string, Pipeline_types.error) result

(** Return obligations dump only. *)

val obligations_dump_data :
  input_file:string -> (obligations_dump_data, Pipeline_types.error) result

(** Execute pipeline and return consolidated dump payload.

    Proof is executed only when [prove=true].
*)

val run_dump_data :
  input_file:string ->
  timeout_s:int ->
  prove:bool ->
  generate_vc_text:bool ->
  generate_smt_text:bool ->
  (run_dump_data, Pipeline_types.error) result

(** Render [.kobj] summary (or compile then render from source input). *)

val kobj_summary :
  input_file:string -> (string, Pipeline_types.error) result

(** Render [.kobj] clause view (or compile then render from source input). *)

val kobj_clauses :
  input_file:string -> (string, Pipeline_types.error) result

(** Render [.kobj] product view (or compile then render from source input). *)

val kobj_product :
  input_file:string -> (string, Pipeline_types.error) result

(** Render [.kobj] summaries view (or compile then render from source input). *)

val kobj_contracts :
  input_file:string -> (string, Pipeline_types.error) result

(** Render normalized IR text for [input_file]. *)

val normalized_program : input_file:string -> (string, Pipeline_types.error) result
(** Render pretty IR text for [input_file]. *)

val ir_pretty_dump : input_file:string -> (string, Pipeline_types.error) result

(** Execute full pipeline with structured [Pipeline_types.config]. *)

val run : Pipeline_types.config -> (Pipeline_types.outputs, Pipeline_types.error) result

(** Execute full pipeline with callbacks for progressive reporting. *)

val run_with_callbacks :
  should_cancel:(unit -> bool) ->
  Pipeline_types.config ->
  on_outputs_ready:(Pipeline_types.outputs -> unit) ->
  on_goals_ready:(string list * int list -> unit) ->
  on_goal_done:(int -> string -> string -> float -> string option -> string option -> unit) ->
  (Pipeline_types.outputs, Pipeline_types.error) result
