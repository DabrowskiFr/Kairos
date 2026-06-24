(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frederic Dabrowski
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

(** Name inspection for generated Why3 Ptree terms, specs, and expressions. *)

module StringSet : Set.S with type elt = string

val names_of_qualid : Why3.Ptree.qualid -> StringSet.t -> StringSet.t
val names_of_term : Why3.Ptree.term -> StringSet.t -> StringSet.t
val names_of_spec : Why3.Ptree.spec -> StringSet.t -> StringSet.t
val names_of_expr : Why3.Ptree.expr -> StringSet.t -> StringSet.t
val term_has_old : Why3.Ptree.term -> bool
