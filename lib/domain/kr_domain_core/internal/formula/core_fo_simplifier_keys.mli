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

val mk_h : Kr_domain_core_syntax.historical Kr_domain_core_syntax.hexpr_desc -> Kr_domain_core_syntax.historical Kr_domain_core_syntax.hexpr
val htrue : Kr_domain_core_syntax.historical Kr_domain_core_syntax.hexpr
val hfalse : Kr_domain_core_syntax.historical Kr_domain_core_syntax.hexpr
val is_htrue : Kr_domain_core_syntax.historical Kr_domain_core_syntax.hexpr -> bool
val is_hfalse : Kr_domain_core_syntax.historical Kr_domain_core_syntax.hexpr -> bool
val key_of_hexpr : Kr_domain_core_syntax.historical Kr_domain_core_syntax.hexpr -> string
val cache_key_of_hexpr : Kr_domain_core_syntax.historical Kr_domain_core_syntax.hexpr -> string

type rel_lit = { subject : string; op : Kr_domain_core_syntax.relop; value : string }

val rel_lit_of_hexpr : Kr_domain_core_syntax.historical Kr_domain_core_syntax.hexpr -> rel_lit option
val literal_key : Kr_domain_core_syntax.historical Kr_domain_core_syntax.hexpr -> (string * bool) option

val are_complements :
  Kr_domain_core_syntax.historical Kr_domain_core_syntax.hexpr -> Kr_domain_core_syntax.historical Kr_domain_core_syntax.hexpr -> bool

val negate_relop : Kr_domain_core_syntax.relop -> Kr_domain_core_syntax.relop

val eval_const_rel :
  Kr_domain_core_syntax.relop ->
  Kr_domain_core_syntax.historical Kr_domain_core_syntax.hexpr ->
  Kr_domain_core_syntax.historical Kr_domain_core_syntax.hexpr ->
  bool option

val flatten_bool :
  Kr_domain_core_syntax.binop ->
  Kr_domain_core_syntax.historical Kr_domain_core_syntax.hexpr ->
  Kr_domain_core_syntax.historical Kr_domain_core_syntax.hexpr list

val dedup_hexprs :
  Kr_domain_core_syntax.historical Kr_domain_core_syntax.hexpr list -> Kr_domain_core_syntax.historical Kr_domain_core_syntax.hexpr list

val length_at_most : int -> 'a list -> bool
val bool_literals_have_complement : Kr_domain_core_syntax.historical Kr_domain_core_syntax.hexpr list -> bool
