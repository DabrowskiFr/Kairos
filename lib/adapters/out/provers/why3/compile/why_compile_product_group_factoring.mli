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
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *---------------------------------------------------------------------------*)

(** Selection of equivalent factorizations for grouped product-step terms. *)

module Boundary = Why_compile_product_group_boundary

type entry_terms = {
  pre_terms : Why3.Ptree.term list;
  post_terms : Why3.Ptree.term list;
}

type result = {
  proof_terms : Boundary.proof_terms;
  profile : Boundary.profile;
}

val build : pre_terms:Why3.Ptree.term list -> entry_terms:entry_terms list -> result
