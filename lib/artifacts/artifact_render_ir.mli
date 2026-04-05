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

(** Text renderers for raw, annotated, and verified Kairos IR nodes. *)

(*---------------------------------------------------------------------------
 * Kairos — Text renderer for the three IR layers.
 *
 * Produces a human-readable `.kir` representation of raw_node,
 * annotated_node, and verified_node.
 *---------------------------------------------------------------------------*)

val render_raw_node : Ir_proof_views.raw_node -> string
val render_annotated_node : Ir_proof_views.annotated_node -> string
val render_verified_node : Ir_proof_views.verified_node -> string

(** Render a full IR program with canonical-contract sections and proof_views.

    The output is intended to be readable while preserving all IR fields. *)
val render_pretty_program : ?source_program:Ast.program option -> Ir.program_ir -> string
