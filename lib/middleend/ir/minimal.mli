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

(** Build minimal canonical summaries from AST control-flow and product automata.

    This pass only performs structural grouping:
    - group key: (program transition, product source, assume guard)
    - branch partition: safe vs bad-guarantee

    It does not compute logical clauses yet. *)

type t = { summaries : Ir.product_step_summary list }

val build :
  node:Ir.node_ir ->
  analysis:Product_build.analysis ->
  program_transitions:Ir.transition list ->
  t

val apply :
  minimal_generation:t ->
  Ir.node_ir ->
  Ir.node_ir

val build_program :
  analyses:(Ast.ident * Product_build.analysis) list ->
  program_transitions_of_node:(Ast.ident -> (Ir.transition list, string) result) ->
  Ir.node_ir list ->
  ((Ast.ident * t) list, string) result

val apply_program :
  minimal_generations:(Ast.ident * t) list ->
  Ir.node_ir list ->
  Ir.node_ir list
