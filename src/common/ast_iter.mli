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

val iter_program : (Ast.node -> unit) -> Ast.program -> unit
val iter_nodes : (Ast.node -> unit) -> Ast.program -> unit
val iter_transitions : (Ast.transition -> unit) -> Ast.program -> unit
val iter_node_transitions : (Ast.node -> Ast.transition -> unit) -> Ast.program -> unit

val fold_nodes : ('a -> Ast.node -> 'a) -> 'a -> Ast.program -> 'a
val fold_transitions : ('a -> Ast.transition -> 'a) -> 'a -> Ast.program -> 'a

val map_program : (Ast.node -> Ast.node) -> Ast.program -> Ast.program
val map_transitions : (Ast.transition -> Ast.transition) -> Ast.program -> Ast.program
val map_node_transitions : (Ast.transition -> Ast.transition) -> Ast.node -> Ast.node
