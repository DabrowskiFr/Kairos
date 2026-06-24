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
open Why_compile_expr

type entry =
  int * Why_contracts.step_contract_info * Why_runtime_view.runtime_transition_view

type t = {
  pre_term : Why3.Ptree.term;
  post_body : Why3.Ptree.term;
  distinct_pre_count : int;
  distinct_post_count : int;
  post_implication_count : int;
  pre_text_bytes : int;
  post_text_bytes : int;
  estimated_cost : int;
}

let unique_term_count terms =
  terms
  |> List.map string_of_term
  |> List.sort_uniq String.compare
  |> List.length

let build ~(env : Why_compile_expr.env) ~(pre_vars_name : string)
    ~(post_vars_name : string) ~step_pre_terms_with_rec
    ~step_post_terms_with_rec (entries : entry list) =
  let pre_terms =
    entries
    |> List.map (fun (_i, sc, _t) ->
           step_pre_terms_with_rec env.rec_name sc |> term_and_list)
  in
  let pre_term = pre_terms |> term_or_list in
  let grouped_post_preconditions =
    let groups = Hashtbl.create 16 in
    let order = ref [] in
    entries
    |> List.iter (fun (_i, sc, _t) ->
           let pre = step_pre_terms_with_rec pre_vars_name sc |> term_and_list in
           let post =
             step_post_terms_with_rec post_vars_name sc |> term_and_list
           in
           if not (Hashtbl.mem groups post) then order := post :: !order;
           let previous =
             Hashtbl.find_opt groups post |> Option.value ~default:[]
           in
           Hashtbl.replace groups post (pre :: previous));
    List.rev !order
    |> List.map (fun post ->
           let pres = Hashtbl.find groups post |> List.rev in
           (term_or_list pres, post))
  in
  let post_body =
    grouped_post_preconditions
    |> List.map (fun (pre, post) -> term_implies pre post)
    |> term_and_list
  in
  let post_terms =
    grouped_post_preconditions |> List.map (fun (_pre, post) -> post)
  in
  let pre_text_bytes = String.length (string_of_term pre_term) in
  let post_text_bytes = String.length (string_of_term post_body) in
  {
    pre_term;
    post_body;
    distinct_pre_count = unique_term_count pre_terms;
    distinct_post_count = unique_term_count post_terms;
    post_implication_count = List.length grouped_post_preconditions;
    pre_text_bytes;
    post_text_bytes;
    estimated_cost = pre_text_bytes + post_text_bytes;
  }
