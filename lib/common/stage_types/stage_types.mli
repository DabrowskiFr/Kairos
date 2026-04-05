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

(** Stage-specific type aliases used to make pipeline intent explicit. *)

(* Parsed AST, directly from the frontend. *)
type parsed = Ast.program

(* Enriched normalized program after contract generation/initial goals. *)
type contracts_stage = Ir.node list

(* Enriched normalized program after instrumentation. *)
type instrumentation_stage = Ir.node list

(* Enriched normalized program ready for Why3-side compilation. *)
type why_stage = Ir.node list
