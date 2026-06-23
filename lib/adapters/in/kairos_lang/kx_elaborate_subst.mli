(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frederic Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *---------------------------------------------------------------------------*)

(** Capture-avoiding substitution over the Kairos surface syntax.

    Elaboration uses this module when expanding indexed declarations,
    specification definitions, predicates, histories, observers, and actions.
    The functions stay on surface terms: they must not know the executable AST,
    the verification model, Why3, or automata.
*)

val subst_ident : param:string -> value:string -> string -> string
val nat_literal_of_ident : string -> int option

val subst_ref :
  param:string ->
  value:string ->
  Kx_surface_syntax.indexed_ref ->
  Kx_surface_syntax.indexed_ref

val subst_nat_expr :
  param:string ->
  value:string ->
  Kx_surface_syntax.nat_expr ->
  Kx_surface_syntax.nat_expr

val subst_expr :
  param:string ->
  value:string ->
  Kx_surface_syntax.expr ->
  Kx_surface_syntax.expr

val subst_hexpr :
  param:string ->
  value:string ->
  Kx_surface_syntax.hexpr ->
  Kx_surface_syntax.hexpr

val subst_spec_arg :
  param:string ->
  value:string ->
  Kx_surface_syntax.spec_arg ->
  Kx_surface_syntax.spec_arg

val subst_ltl :
  param:string ->
  value:string ->
  Kx_surface_syntax.ltl ->
  Kx_surface_syntax.ltl

val subst_stmt :
  param:string ->
  value:string ->
  Kx_surface_syntax.stmt ->
  Kx_surface_syntax.stmt

val subst_history_expr :
  param:string ->
  value:string ->
  Kx_surface_syntax.history_expr ->
  Kx_surface_syntax.history_expr
