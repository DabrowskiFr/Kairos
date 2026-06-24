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

(** Small Why3 Ptree term/spec constructors. *)

val empty_spec : unit -> Why3.Ptree.spec
val term_and : Why3.Ptree.term -> Why3.Ptree.term -> Why3.Ptree.term
val term_and_list : Why3.Ptree.term list -> Why3.Ptree.term
val term_or : Why3.Ptree.term -> Why3.Ptree.term -> Why3.Ptree.term
val term_or_list : Why3.Ptree.term list -> Why3.Ptree.term
