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

(** Structural queries and small utilities over the source AST. *)

(** Render a source location in a compact human-readable form. *)
val loc_to_string : Loc.loc -> string

(** Names of the input variables declared by a node. *)
val input_names_of_node : Ast.node -> Core_syntax.ident list

(** Names of the output variables declared by a node. *)
val output_names_of_node : Ast.node -> Core_syntax.ident list

(** Build an index from source state names to their outgoing transitions. *)
val transitions_from_state_fn : Ast.node -> Core_syntax.ident -> Ast.transition list
