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

(** Logging helpers shared by the CLI and editor integrations. *)

(* Configure logging level and optional file output. *)
(** [setup] service entrypoint. *)

val setup : level:Logs.level option -> log_file:string option -> unit

(* Emit a debug message. *)
(** [debug] service entrypoint. *)

val debug : string -> unit

(* Emit an info message. *)
(** [info] service entrypoint. *)

val info : string -> unit

(* Mark the start of a stage (for timing). *)
(** [flow_start] service entrypoint. *)

val flow_start : string -> unit

(* Mark the end of a stage with elapsed ms and key/value stats. *)
(** [flow_end] service entrypoint. *)

val flow_end : string -> int -> (string * string) list -> unit

(* Emit a structured info message for a stage (or global). *)
(** [flow_info] service entrypoint. *)

val flow_info : string option -> string -> (string * string) list -> unit

(* Report that an output file was written (path, kind, bytes). *)
(** [output_written] service entrypoint. *)

val output_written : string -> string -> int -> unit

(* Emit a warning (optionally tied to a stage). *)
(** [warning] service entrypoint. *)

val warning : ?stage:string -> string -> unit

(* Emit an error (optionally tied to a stage). *)
(** [error] service entrypoint. *)

val error : ?stage:string -> string -> unit
