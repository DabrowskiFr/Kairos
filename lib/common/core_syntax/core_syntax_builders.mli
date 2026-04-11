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

(** Constructors and helpers for [Core_syntax].

    This module provides concise constructors to build expressions with optional
    source locations, plus utility conversions between [expr] and [hexpr]. *)

(** [mk_expr ?loc d] builds an imperative expression described by [d]. *)
val mk_expr : ?loc:Loc.loc -> Core_syntax.expr_desc -> Core_syntax.expr

(** [with_expr_desc e d] replaces the descriptor of [e] with [d], preserving
    source location. *)
val with_expr_desc : Core_syntax.expr -> Core_syntax.expr_desc -> Core_syntax.expr

(** [mk_var x] builds the imperative variable [x]. *)
val mk_var : Core_syntax.ident -> Core_syntax.expr

(** [mk_int n] builds the imperative integer literal [n]. *)
val mk_int : int -> Core_syntax.expr

(** [mk_bool b] builds the imperative boolean literal [b]. *)
val mk_bool : bool -> Core_syntax.expr

(** [mk_hexpr ?loc d] builds a historical expression described by [d]. *)
val mk_hexpr : ?loc:Loc.loc -> Core_syntax.hexpr_desc -> Core_syntax.hexpr

(** [with_hexpr_desc h d] replaces the descriptor of [h] with [d], preserving
    source location. *)
val with_hexpr_desc : Core_syntax.hexpr -> Core_syntax.hexpr_desc -> Core_syntax.hexpr

(** [mk_hvar x] builds the historical variable [x]. *)
val mk_hvar : Core_syntax.ident -> Core_syntax.hexpr

(** [mk_hint n] builds the historical integer literal [n]. *)
val mk_hint : int -> Core_syntax.hexpr

(** [mk_hbool b] builds the historical boolean literal [b]. *)
val mk_hbool : bool -> Core_syntax.hexpr

(** [mk_hpre_k x k] builds [pre_k(x,k)] at the historical level. *)
val mk_hpre_k : Core_syntax.ident -> int -> Core_syntax.hexpr

(** [hexpr_of_expr e] structurally converts [e] into the historical layer,
    preserving source location. *)
val hexpr_of_expr : Core_syntax.expr -> Core_syntax.hexpr
