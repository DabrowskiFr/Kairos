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
val mk_iexpr : ?loc:Ast.loc -> Ast.iexpr_desc -> Ast.iexpr

(** Extract the underlying descriptor from an immediate expression. *)
val iexpr_desc : Ast.iexpr -> Ast.iexpr_desc

(** Replace the descriptor while preserving the source location. *)
val with_iexpr_desc : Ast.iexpr -> Ast.iexpr_desc -> Ast.iexpr

(** Convenience constructor for a variable expression. *)
val mk_var : Ast.ident -> Ast.iexpr

(** Convenience constructor for an integer literal. *)
val mk_int : int -> Ast.iexpr

(** Convenience constructor for a boolean literal. *)
val mk_bool : bool -> Ast.iexpr

(** Return the identifier when the expression is a variable. *)
val as_var : Ast.iexpr -> Ast.ident option

(** Build a historical expression with an optional source location. *)
val mk_hexpr : ?loc:Ast.loc -> Ast.hexpr_desc -> Ast.hexpr

(** Extract the underlying descriptor from a historical expression. *)
val hexpr_desc : Ast.hexpr -> Ast.hexpr_desc

(** Replace the descriptor while preserving the source location. *)
val with_hexpr_desc : Ast.hexpr -> Ast.hexpr_desc -> Ast.hexpr

(** Convenience constructors for historical expressions. *)
val mk_hvar : Ast.ident -> Ast.hexpr
val mk_hint : int -> Ast.hexpr
val mk_hbool : bool -> Ast.hexpr
val mk_hpre_k : Ast.ident -> int -> Ast.hexpr

(** Return the identifier when the historical expression is a variable. *)
val as_hvar : Ast.hexpr -> Ast.ident option

(** Embed a non-temporal expression into the historical syntax. *)
val hexpr_of_iexpr : Ast.iexpr -> Ast.hexpr

(** Project a historical expression to non-temporal syntax when it contains no
    [pre]/[pre_k] reference. *)
val iexpr_of_hexpr : Ast.hexpr -> Ast.iexpr option

(** Build a statement with an optional source location. *)
val mk_stmt : ?loc:Ast.loc -> Ast.stmt_desc -> Ast.stmt

(** Extract the underlying descriptor from a statement. *)
val stmt_desc : Ast.stmt -> Ast.stmt_desc

(** Replace the descriptor while preserving the source location. *)
val with_stmt_desc : Ast.stmt -> Ast.stmt_desc -> Ast.stmt

(** Build a source transition. *)
val mk_transition :
  src:Ast.ident ->
  dst:Ast.ident ->
  guard:Ast.iexpr option ->
  body:Ast.stmt list ->
  Ast.transition

(** Build a source node. *)
val mk_node :
  nname:Ast.ident ->
  inputs:Ast.vdecl list ->
  outputs:Ast.vdecl list ->
  assumes:Ast.ltl list ->
  guarantees:Ast.ltl list ->
  instances:(Ast.ident * Ast.ident) list ->
  locals:Ast.vdecl list ->
  states:Ast.ident list ->
  init_state:Ast.ident ->
  trans:Ast.transition list ->
  Ast.node
