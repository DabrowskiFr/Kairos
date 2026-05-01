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

(** Small helpers to decode JSON-RPC/LSP request payloads. *)

val position_from_params : Yojson.Safe.t -> (int * int) option

(** [get_param_string] service entrypoint. *)

val get_param_string : Yojson.Safe.t -> string -> string option
(** [get_param_bool] service entrypoint. *)

val get_param_bool : Yojson.Safe.t -> string -> bool -> bool
(** [get_param_int] service entrypoint. *)

val get_param_int : Yojson.Safe.t -> string -> int -> int
(** [get_param_list] service entrypoint. *)

val get_param_list : Yojson.Safe.t -> string -> Yojson.Safe.t list option

(** [get_text_document_uri] service entrypoint. *)

val get_text_document_uri : Yojson.Safe.t -> string option
(** [get_did_open_text] service entrypoint. *)

val get_did_open_text : Yojson.Safe.t -> string option
(** [get_did_change_text] service entrypoint. *)

val get_did_change_text : Yojson.Safe.t -> string option
(** [client_supports_work_done_progress] service entrypoint. *)

val client_supports_work_done_progress : Yojson.Safe.t -> bool

(** [map_outputs] service entrypoint. *)

val map_outputs : Pipeline_types.outputs -> Lsp_protocol.outputs
(** [map_automata] service entrypoint. *)

val map_automata : Pipeline_types.automata_outputs -> Lsp_protocol.automata_outputs
(** [map_why] service entrypoint. *)

val map_why : Pipeline_types.why_outputs -> Lsp_protocol.why_outputs
(** [map_oblig] service entrypoint. *)

val map_oblig : Pipeline_types.obligations_outputs -> Lsp_protocol.obligations_outputs
