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

(** Build normalized nodes directly from source AST nodes. *)

val of_ast_transition : Ast.transition -> Ir.transition

val of_ast_summary_formula :
  ?origin:Formula_origin.t ->
  Ast.ltl_o ->
  Ir.summary_formula

val of_ast_node : Ast.node -> Ir.node_ir

val of_ast_program : Ast.program -> Ir.node_ir list
