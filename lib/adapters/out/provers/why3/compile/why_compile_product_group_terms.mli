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

(** Construction of symbolic terms for grouped product-step helpers. *)

module Boundary = Why_compile_product_group_boundary

type entry = Boundary.entry
type t = Boundary.t

val build :
  env:Why_compile_expr.env ->
  pre_vars_name:string ->
  post_vars_name:string ->
  step_pre_terms_with_rec:
    (string -> Why_contracts.step_contract_info -> Why3.Ptree.term list) ->
  step_post_terms_with_rec:
    (string -> Why_contracts.step_contract_info -> Why3.Ptree.term list) ->
  entry list ->
  t

val proof_terms : t -> Boundary.proof_terms
val profile : t -> Boundary.profile
