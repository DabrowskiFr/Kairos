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

(** Text view of IR nodes rendered as an executable-looking normalized program.

    This renderer is aimed at code-oriented reading (signature, contracts,
    transitions), not at proof internals. *)

(** Render one normalized transition. *)
val render_transition : ?indent:int -> Ir.transition -> string

(** Render one IR node in "program view". *)
val render_node : ?source_program:Ast.program option -> Ir.node_ir -> string

(** Render a full IR program in "program view". *)
val render_program : ?source_program:Ast.program option -> Ir.node_ir list -> string
