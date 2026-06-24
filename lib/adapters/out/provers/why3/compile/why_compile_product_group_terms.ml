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

open Why_compile_ptree_helpers
module Boundary = Why_compile_product_group_boundary
module Factoring = Why_compile_product_group_factoring

type entry = Boundary.entry
type t = Boundary.t

let build ~(env : Why_compile_expr.env) ~(pre_vars_name : string)
    ~(post_vars_name : string) ~step_pre_terms_with_rec
    ~step_post_terms_with_rec (entries : entry list) =
  let pre_terms =
    entries
    |> List.map (fun (_i, sc, _t) ->
           step_pre_terms_with_rec env.rec_name sc |> term_and_list)
  in
  let entry_terms =
    entries
    |> List.map (fun (_i, sc, _t) ->
           {
             Factoring.pre_terms = step_pre_terms_with_rec pre_vars_name sc;
             post_terms = step_post_terms_with_rec post_vars_name sc;
           })
  in
  let factored = Factoring.build ~pre_terms ~entry_terms in
  Boundary.make factored.proof_terms factored.profile

let proof_terms = Boundary.proof_terms

let profile = Boundary.profile
