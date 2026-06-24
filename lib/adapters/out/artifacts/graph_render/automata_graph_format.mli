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

(** Formula and label formatting shared by automata graph renderers. *)

val render_automaton_lines : prefix:string -> string list -> string list
val strip_braces : string -> string
val rewrite_history_vars : string -> string
val pretty_product_formula : Core_syntax.hexpr -> string
val pretty_plain_dot_formula : Core_syntax.hexpr -> string
val subscript_digits : int -> string
val pretty_aut_state : prefix:string -> idx:int -> bad_idx:int -> string
val tau_alias : int -> string
val phi_alias : int -> string
val wrap_formula_lines : ?max_width:int -> string -> string list
val compact_display_string : string -> string
