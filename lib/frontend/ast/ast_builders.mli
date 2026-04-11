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

(** Constructors and utility helpers for the AST.

   These helpers centralize defaults (locations) and make parser/transform code more compact. *)

(** Build an immediate expression with an optional source location. *)
val mk_iexpr : ?loc:Core_syntax.loc -> Core_syntax.iexpr_desc -> Core_syntax.iexpr

(** Extract the underlying descriptor from an immediate expression. *)
val iexpr_desc : Core_syntax.iexpr -> Core_syntax.iexpr_desc

(** Replace the descriptor while preserving the source location. *)
val with_iexpr_desc : Core_syntax.iexpr -> Core_syntax.iexpr_desc -> Core_syntax.iexpr

(** Convenience constructor for a variable expression. *)
val mk_var : Core_syntax.ident -> Core_syntax.iexpr

(** Convenience constructor for an integer literal. *)
val mk_int : int -> Core_syntax.iexpr

(** Convenience constructor for a boolean literal. *)
val mk_bool : bool -> Core_syntax.iexpr

(** Return the identifier when the expression is a variable. *)
val as_var : Core_syntax.iexpr -> Core_syntax.ident option

(** Build a historical expression with an optional source location. *)
val mk_hexpr : ?loc:Core_syntax.loc -> Core_syntax.hexpr_desc -> Core_syntax.hexpr

(** Extract the underlying descriptor from a historical expression. *)
val hexpr_desc : Core_syntax.hexpr -> Core_syntax.hexpr_desc

(** Replace the descriptor while preserving the source location. *)
val with_hexpr_desc : Core_syntax.hexpr -> Core_syntax.hexpr_desc -> Core_syntax.hexpr

(** Convenience constructors for historical expressions. *)
val mk_hvar : Core_syntax.ident -> Core_syntax.hexpr
val mk_hint : int -> Core_syntax.hexpr
val mk_hbool : bool -> Core_syntax.hexpr
val mk_hpre_k : Core_syntax.ident -> int -> Core_syntax.hexpr

(** Return the identifier when the historical expression is a variable. *)
val as_hvar : Core_syntax.hexpr -> Core_syntax.ident option

(** Embed a non-temporal expression into the historical syntax. *)
val hexpr_of_iexpr : Core_syntax.iexpr -> Core_syntax.hexpr

(** Project a historical expression to non-temporal syntax when it contains no
    [pre]/[pre_k] reference. *)
val iexpr_of_hexpr : Core_syntax.hexpr -> Core_syntax.iexpr option

(**********************)

(** Build a statement with an optional source location. *)
val mk_stmt : ?loc:Core_syntax.loc -> Ast.stmt_desc -> Ast.stmt

(** Extract the underlying descriptor from a statement. *)
val stmt_desc : Ast.stmt -> Ast.stmt_desc

(** Replace the descriptor while preserving the source location. *)
val with_stmt_desc : Ast.stmt -> Ast.stmt_desc -> Ast.stmt

(** Build a source transition. *)
val mk_transition :
  src:Core_syntax.ident ->
  dst:Core_syntax.ident ->
  guard:Core_syntax.iexpr option ->
  body:Ast.stmt list ->
  Ast.transition

(** Build a source node. *)
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
