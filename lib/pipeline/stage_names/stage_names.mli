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

(** Logical identifiers for pipeline stages, mainly used in logs and UI
    diagnostics. *)
type stage_id = Parsed | Automaton | Summaries | Instrumentation | Why | Prove

(** All known pipeline stages, in declaration order. *)
val all : stage_id list

(** Stages that stop before backend-specific proof generation. *)
val ast_stages : stage_id list

(** Parse a stage identifier from its stable string representation. *)
val of_string : string -> (stage_id, string) result

(** Stable textual name used in logs, JSON, and UI payloads. *)
val to_string : stage_id -> string

(** Short human-readable explanation of the role of a stage. *)
val description : stage_id -> string
