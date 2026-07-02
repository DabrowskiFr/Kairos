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
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *---------------------------------------------------------------------------*)

(** Structural keys and literal classifiers used by the FO simplifier. *)

module StringSet : Set.S with type elt = string

val mk_h : Core_syntax.hexpr_desc -> Core_syntax.hexpr
val htrue : Core_syntax.hexpr
val hfalse : Core_syntax.hexpr
val is_htrue : Core_syntax.hexpr -> bool
val is_hfalse : Core_syntax.hexpr -> bool
val key_of_hexpr : Core_syntax.hexpr -> string

type rel_lit = { subject : string; op : Core_syntax.relop; value : string }

val rel_lit_of_hexpr : Core_syntax.hexpr -> rel_lit option
val literal_key : Core_syntax.hexpr -> (string * bool) option
val are_complements : Core_syntax.hexpr -> Core_syntax.hexpr -> bool
val negate_relop : Core_syntax.relop -> Core_syntax.relop
val eval_const_rel : Core_syntax.relop -> Core_syntax.hexpr -> Core_syntax.hexpr -> bool option
val flatten_bool : Core_syntax.binop -> Core_syntax.hexpr -> Core_syntax.hexpr list
val dedup_hexprs : Core_syntax.hexpr list -> Core_syntax.hexpr list
val length_at_most : int -> 'a list -> bool
val string_set_of_keys : string list -> StringSet.t
val keyed_hexprs : Core_syntax.hexpr list -> (string * Core_syntax.hexpr) list
val bool_literals_have_complement : Core_syntax.hexpr list -> bool
