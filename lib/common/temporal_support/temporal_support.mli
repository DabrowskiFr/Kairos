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

    This module groups the operations around:
    {ul
    {- [pre_k] expressions;}
    {- bounded history slots;}
    {- LTL shifting by a finite number of ticks.}} *)

(** Metadata attached to one history expression.

    - [expr] is the memorized expression.
    - [names] are the slot names, from most recent to oldest.
    - [vty] is the slot type. *)
type pre_k_info = { h : Core_syntax.hexpr; expr : Core_syntax.expr; names : string list; vty : Core_syntax.ty }
[@@deriving yojson]

(** Result of normalizing an LTL formula with respect to the maximum [X]-depth
    it requires. *)
type ltl_norm = { ltl : Core_syntax.ltl; k_guard : int option }

(** Maximum nesting depth of [X] operators in a formula. *)
val max_x_depth : Core_syntax.ltl -> int

(** Decide whether an expression can safely stay in the current tick when
    history is shifted. *)
val is_const_expr : Core_syntax.expr -> bool

(** Shift one history expression by [shift] ticks when representable. *)
val shift_hexpr_by : init_for_var:(Core_syntax.ident -> Core_syntax.expr) -> int -> Core_syntax.hexpr -> Core_syntax.hexpr option

(** Normalize an LTL formula and record the required [X]-depth in [k_guard]. *)
val normalize_ltl_for_k : init_for_var:(Core_syntax.ident -> Core_syntax.expr) -> Core_syntax.ltl -> ltl_norm

(** Shift an entire LTL formula by [shift] ticks when representable. *)
val shift_ltl_by : init_for_var:(Core_syntax.ident -> Core_syntax.expr) -> int -> Core_syntax.ltl -> Core_syntax.ltl option
