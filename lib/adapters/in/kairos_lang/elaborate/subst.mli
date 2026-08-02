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
(** Replace an identifier when it is exactly the named parameter. *)

val nat_literal_of_ident : string -> int option
(** Interpret a non-negative decimal identifier as a natural literal. *)

val subst_ref :
  param:string ->
  value:string ->
  Surface.Syntax.indexed_ref ->
  Surface.Syntax.indexed_ref
(** Substitute an identifier through a possibly indexed reference. *)

val subst_nat_expr :
  param:string ->
  value:string ->
  Surface.Syntax.nat_expr ->
  Surface.Syntax.nat_expr
(** Substitute a natural parameter, turning a numeric value into a literal. *)

val subst_expr :
  param:string ->
  value:string ->
  Surface.Syntax.expr ->
  Surface.Syntax.expr
(** Substitute an identifier throughout an executable expression. *)

val subst_hexpr :
  param:string ->
  value:string ->
  Surface.Syntax.hexpr ->
  Surface.Syntax.hexpr
(** Substitute an identifier throughout a historical expression. *)

val subst_spec_arg :
  param:string ->
  value:string ->
  Surface.Syntax.spec_arg ->
  Surface.Syntax.spec_arg
(** Substitute an identifier throughout a specification argument. *)

val subst_ltl :
  param:string ->
  value:string ->
  Surface.Syntax.ltl ->
  Surface.Syntax.ltl
(** Substitute an identifier throughout a temporal formula. *)

val subst_stmt :
  param:string ->
  value:string ->
  Surface.Ast.stmt ->
  Surface.Ast.stmt
(** Substitute an identifier throughout an executable statement. *)

val subst_expr_actual :
  param:string ->
  actual:Surface.Syntax.expr ->
  Surface.Syntax.expr ->
  Surface.Syntax.expr
(** Replace free scalar occurrences of a formal parameter with an executable
    actual expression. *)

val subst_hexpr_actual :
  param:string ->
  actual:Surface.Syntax.expr ->
  Surface.Syntax.hexpr ->
  Surface.Syntax.hexpr
(** Replace free scalar occurrences of a formal parameter inside a historical
    expression with an executable actual expression. *)

val subst_stmt_actual :
  param:string ->
  actual:Surface.Syntax.expr ->
  Surface.Ast.stmt ->
  Surface.Ast.stmt
(** Replace free scalar occurrences of a formal parameter throughout a
    statement. *)

val subst_history_expr :
  param:string ->
  value:string ->
  Surface.Syntax.history_expr ->
  Surface.Syntax.history_expr
(** Substitute an identifier throughout a named history declaration. *)
