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

(** Presentation labels attached to product-step proof obligations. *)

val product_step_preconditions : string
val product_step_postconditions : string
val grouped_product_preconditions : string
val shared_postcondition_facts : string

val repeated : string -> 'a list -> string list

val individual_post_labels :
  bundle_post_terms:bool ->
  raw_post_terms:'a list ->
  raw_post_labels:string list ->
  string list
