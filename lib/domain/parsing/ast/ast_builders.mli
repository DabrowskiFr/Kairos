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

(** Constructors and utility helpers for the AST layer only. *)

val mk_stmt : ?loc:Loc.loc -> Ast.stmt_desc -> Ast.stmt
(** [stmt_desc] service entrypoint. *)

val stmt_desc : Ast.stmt -> Ast.stmt_desc
(** [with_stmt_desc] service entrypoint. *)

val with_stmt_desc : Ast.stmt -> Ast.stmt_desc -> Ast.stmt

(** [mk_transition] service entrypoint. *)

val mk_transition :
  src:Core_syntax.ident ->
  dst:Core_syntax.ident ->
  guard:Core_syntax.expr option ->
  body:Ast.stmt list ->
  Ast.transition

(** [mk_node] service entrypoint. *)

val mk_node :
  nname:Core_syntax.ident ->
  inputs:Core_syntax.vdecl list ->
  outputs:Core_syntax.vdecl list ->
  assumes:Core_syntax.ltl list ->
  guarantees:Core_syntax.ltl list ->
  instances:(Core_syntax.ident * Core_syntax.ident) list ->
  locals:Core_syntax.vdecl list ->
  states:Core_syntax.ident list ->
  init_state:Core_syntax.ident ->
  trans:Ast.transition list ->
  Ast.node
