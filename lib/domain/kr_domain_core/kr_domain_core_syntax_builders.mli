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

(** Constructors and helpers for [Kr_domain_core_syntax].

    This module provides concise constructors to build expressions with optional
    source locations, plus utility conversions between [expr] and [hexpr]. *)

(** [mk_expr ?loc d] builds an imperative expression described by [d]. *)
val mk_expr : ?loc:Kr_domain_core_locations.loc -> Kr_domain_core_syntax.expr_desc -> Kr_domain_core_syntax.expr

(** [with_expr_desc e d] replaces the descriptor of [e] with [d], preserving
    source location. *)
val with_expr_desc : Kr_domain_core_syntax.expr -> Kr_domain_core_syntax.expr_desc -> Kr_domain_core_syntax.expr

(** [mk_var x] builds the imperative variable [x]. *)
val mk_var : Kr_domain_core_syntax.ident -> Kr_domain_core_syntax.expr

(** [mk_int n] builds the imperative integer literal [n]. *)
val mk_int : int -> Kr_domain_core_syntax.expr

(** [mk_bool b] builds the imperative boolean literal [b]. *)
val mk_bool : bool -> Kr_domain_core_syntax.expr

(** [mk_enum c] builds the imperative enum constructor literal [c]. *)
val mk_enum : Kr_domain_core_syntax.ident -> Kr_domain_core_syntax.expr

(** [mk_hexpr ?loc d] builds a historical expression described by [d]. *)
val mk_hexpr :
  ?loc:Kr_domain_core_locations.loc ->
  'phase Kr_domain_core_syntax.hexpr_desc ->
  'phase Kr_domain_core_syntax.hexpr

(** [with_hexpr_desc h d] replaces the descriptor of [h] with [d], preserving
    source location. *)
val with_hexpr_desc :
  'phase Kr_domain_core_syntax.hexpr ->
  'phase Kr_domain_core_syntax.hexpr_desc ->
  'phase Kr_domain_core_syntax.hexpr

(** [mk_hvar x] builds the historical variable [x]. *)
val mk_hvar : Kr_domain_core_syntax.ident -> 'phase Kr_domain_core_syntax.hexpr

(** [mk_hint n] builds the historical integer literal [n]. *)
val mk_hint : int -> 'phase Kr_domain_core_syntax.hexpr

(** [mk_hbool b] builds the historical boolean literal [b]. *)
val mk_hbool : bool -> 'phase Kr_domain_core_syntax.hexpr

(** [mk_henum c] builds the historical enum constructor literal [c]. *)
val mk_henum : Kr_domain_core_syntax.ident -> 'phase Kr_domain_core_syntax.hexpr

(** [mk_hpre_k x k] builds [pre_k(x,k)] at the historical level. *)
val mk_hpre_k :
  Kr_domain_core_syntax.ident -> int -> Kr_domain_core_syntax.historical Kr_domain_core_syntax.hexpr

(** [mk_hpred p args] builds a boolean predicate application [p(args)]. *)
val mk_hpred :
  Kr_domain_core_syntax.ident ->
  'phase Kr_domain_core_syntax.hexpr list ->
  'phase Kr_domain_core_syntax.hexpr

(** [mk_hnot h] builds [not h]. *)
val mk_hnot : 'phase Kr_domain_core_syntax.hexpr -> 'phase Kr_domain_core_syntax.hexpr

(** [mk_hand a b] builds [a and b]. *)
val mk_hand :
  'phase Kr_domain_core_syntax.hexpr ->
  'phase Kr_domain_core_syntax.hexpr ->
  'phase Kr_domain_core_syntax.hexpr

(** [mk_hor a b] builds [a or b]. *)
val mk_hor :
  'phase Kr_domain_core_syntax.hexpr ->
  'phase Kr_domain_core_syntax.hexpr ->
  'phase Kr_domain_core_syntax.hexpr

(** [mk_himp a b] builds [a -> b] as [not a or b]. *)
val mk_himp :
  'phase Kr_domain_core_syntax.hexpr ->
  'phase Kr_domain_core_syntax.hexpr ->
  'phase Kr_domain_core_syntax.hexpr

(** [hexpr_of_expr e] structurally converts [e] into the historical layer,
    preserving source location. *)
val hexpr_of_expr :
  Kr_domain_core_syntax.expr -> Kr_domain_core_syntax.history_free Kr_domain_core_syntax.hexpr
