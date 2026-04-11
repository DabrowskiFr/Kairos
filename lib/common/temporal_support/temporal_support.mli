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

(** Shared helpers for bounded temporal history.

    This module provides the pure transformations used by the temporal passes:
    {ul
    {- representation metadata for [pre_k] history slots;}
    {- finite shifts on historical formulas ([hexpr]) and LTL formulas;}
    {- normalization of LTL formulas w.r.t. the maximal [X]-depth.}
    }

    These functions do not mutate IR structures: they only rewrite formulas. *)

(** Metadata attached to one temporal history source.

    The record links one source variable to the runtime slots used to materialize
    bounded history:
    {ul
    {- [var_name]: source variable name used by [pre_k];}
    {- [names]: generated slot identifiers ordered by increasing depth
       ([pre_k1], [pre_k2], ...);}
    {- [vty]: type of the stored values.}
    } *)
type pre_k_info = { var_name : Core_syntax.ident; names : string list; vty : Core_syntax.ty }
[@@deriving yojson]

(** Result of LTL normalization with explicit shift depth.

    [k_guard] is [Some k] when the normalized formula required aligning [X]-nesting
    to depth [k], and [None] when no [X] shift was needed. *)
type ltl_norm = { ltl : Core_syntax.ltl; k_guard : int option }

(** [max_x_depth f] returns the maximum nesting depth of [X] in [f]. *)
val max_x_depth : Core_syntax.ltl -> int

(** [is_const_expr e] returns [true] for expressions that are considered tick-invariant
    by the temporal utilities.

    The current implementation treats literals and internal [Aut<digits>] names
    as constant. *)
val is_const_expr : Core_syntax.expr -> bool

(** [shift_hexpr_by ~init_for_var shift h] shifts historical references in [h]
    by [shift] ticks.

    - [shift <= 0] returns [Some h].
    - On success, each [HVar v] becomes [HPreK (v, shift)] and each
      [HPreK (v, k)] becomes [HPreK (v, k + shift)].
    - Returns [None] when a sub-expression cannot be shifted. *)
val shift_hexpr_by : init_for_var:(Core_syntax.ident -> Core_syntax.expr) -> int -> Core_syntax.hexpr -> Core_syntax.hexpr option

(** [normalize_ltl_for_k ~init_for_var f] normalizes [f] by aligning nested [X]
    to a single maximal depth and returns that depth in [k_guard]. *)
val normalize_ltl_for_k : init_for_var:(Core_syntax.ident -> Core_syntax.expr) -> Core_syntax.ltl -> ltl_norm

(** [shift_ltl_by ~init_for_var shift f] applies a finite temporal shift to all
    atom-level historical references in [f].

    Returns [None] when one shifted atom cannot be represented. *)
val shift_ltl_by : init_for_var:(Core_syntax.ident -> Core_syntax.expr) -> int -> Core_syntax.ltl -> Core_syntax.ltl option
