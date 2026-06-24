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

open Why_compile_ptree_helpers
open Why_compile_expr
module Boundary = Why_compile_product_group_boundary
module StringSet = Why_compile_ptree_helpers.StringSet

type entry_terms = {
  pre_terms : Why3.Ptree.term list;
  post_terms : Why3.Ptree.term list;
}

type result = {
  proof_terms : Boundary.proof_terms;
  profile : Boundary.profile;
}

type candidate = {
  candidate_kind : Boundary.factor_kind;
  candidate_body : Why3.Ptree.term;
  candidate_body_bytes : int;
  candidate_distinct_post_count : int;
  candidate_post_implication_count : int;
}

type term_cache = { keys : (Why3.Ptree.term, string) Hashtbl.t }

let create_term_cache () = { keys = Hashtbl.create 256 }

let term_key cache term =
  match Hashtbl.find_opt cache.keys term with
  | Some key -> key
  | None ->
      let key = string_of_term term in
      Hashtbl.add cache.keys term key;
      key

let term_size cache term = String.length (term_key cache term)

let unique_term_count cache terms =
  terms
  |> List.fold_left
       (fun acc term -> StringSet.add (term_key cache term) acc)
       StringSet.empty
  |> StringSet.cardinal

let string_set_of_terms cache terms =
  terms
  |> List.fold_left
       (fun acc term -> StringSet.add (term_key cache term) acc)
       StringSet.empty

let common_terms cache terms_by_entry =
  match terms_by_entry with
  | [] -> []
  | first :: rest ->
      let common_keys =
        rest
        |> List.fold_left
             (fun acc terms ->
               StringSet.inter acc (string_set_of_terms cache terms))
             (string_set_of_terms cache first)
      in
      first
      |> List.filter (fun term ->
             StringSet.mem (term_key cache term) common_keys)

let remove_terms cache terms removed =
  let removed_keys = string_set_of_terms cache removed in
  terms
  |> List.filter (fun term ->
         not (StringSet.mem (term_key cache term) removed_keys))

let candidate cache ~kind ~body ~distinct_terms ~implications =
  {
    candidate_kind = kind;
    candidate_body = body;
    candidate_body_bytes = term_size cache body;
    candidate_distinct_post_count = unique_term_count cache distinct_terms;
    candidate_post_implication_count = List.length implications;
  }

let estimated_candidate_cost ~pre_text_bytes candidate =
  pre_text_bytes + candidate.candidate_body_bytes

let grouped_post_preconditions entry_terms ~pre_of_entry ~post_of_entry =
  let groups = Hashtbl.create 16 in
  let order = ref [] in
  entry_terms
  |> List.iter (fun { pre_terms; post_terms } ->
         let pre = pre_of_entry pre_terms in
         let post = post_of_entry post_terms in
         if not (Hashtbl.mem groups post) then order := post :: !order;
         let previous =
           Hashtbl.find_opt groups post |> Option.value ~default:[]
         in
         Hashtbl.replace groups post (pre :: previous));
  List.rev !order
  |> List.map (fun post ->
         let pres = Hashtbl.find groups post |> List.rev in
         (term_or_list pres, post))

let implication_terms grouped =
  grouped
  |> List.filter_map (fun (pre, post) ->
         match (post : Why3.Ptree.term).Why3.Ptree.term_desc with
         | Why3.Ptree.Ttrue -> None
         | _ -> Some (term_implies pre post))

let build ~pre_terms ~entry_terms =
  let cache = create_term_cache () in
  let pre_term = pre_terms |> term_or_list in
  let common_pre_terms_for_group =
    entry_terms |> List.map (fun entry -> entry.pre_terms) |> common_terms cache
  in
  let common_post_terms_for_group =
    entry_terms |> List.map (fun entry -> entry.post_terms) |> common_terms cache
  in
  let original_grouped_post_preconditions =
    grouped_post_preconditions entry_terms ~pre_of_entry:term_and_list
      ~post_of_entry:term_and_list
  in
  let original_implications =
    implication_terms original_grouped_post_preconditions
  in
  let original_candidate =
    candidate cache ~kind:Boundary.Original
      ~body:(term_and_list original_implications)
      ~distinct_terms:(List.map snd original_grouped_post_preconditions)
      ~implications:original_implications
  in
  let post_factored_grouped_post_preconditions =
    grouped_post_preconditions entry_terms ~pre_of_entry:term_and_list
      ~post_of_entry:(fun post_terms ->
        remove_terms cache post_terms common_post_terms_for_group
        |> term_and_list)
  in
  let full_pre_snapshot_terms =
    entry_terms |> List.map (fun entry -> term_and_list entry.pre_terms)
  in
  let common_post_implications ~pre_terms =
    match common_post_terms_for_group with
    | [] -> []
    | terms -> [ term_implies (term_or_list pre_terms) (term_and_list terms) ]
  in
  let post_factored_implications =
    common_post_implications ~pre_terms:full_pre_snapshot_terms
    @ implication_terms post_factored_grouped_post_preconditions
  in
  let post_factored_candidate =
    candidate cache ~kind:Boundary.Post_common
      ~body:(term_and_list post_factored_implications)
      ~distinct_terms:
        (common_post_terms_for_group
        @ List.map snd post_factored_grouped_post_preconditions)
      ~implications:post_factored_implications
  in
  let residual_pre_terms pre_terms =
    remove_terms cache pre_terms common_pre_terms_for_group
  in
  let pre_factored_grouped_post_preconditions =
    grouped_post_preconditions entry_terms
      ~pre_of_entry:(fun pre_terms ->
        residual_pre_terms pre_terms |> term_and_list)
      ~post_of_entry:term_and_list
  in
  let wrap_common_pre inner_implications =
    match common_pre_terms_for_group with
    | [] -> inner_implications
    | terms ->
        [ term_implies (term_and_list terms) (term_and_list inner_implications) ]
  in
  let pre_factored_implications =
    implication_terms pre_factored_grouped_post_preconditions |> wrap_common_pre
  in
  let pre_factored_candidate =
    candidate cache ~kind:Boundary.Pre_common
      ~body:(term_and_list pre_factored_implications)
      ~distinct_terms:(List.map snd pre_factored_grouped_post_preconditions)
      ~implications:pre_factored_implications
  in
  let residual_pre_snapshot_terms =
    entry_terms
    |> List.map (fun entry ->
           residual_pre_terms entry.pre_terms |> term_and_list)
  in
  let combined_grouped_post_preconditions =
    grouped_post_preconditions entry_terms
      ~pre_of_entry:(fun pre_terms ->
        residual_pre_terms pre_terms |> term_and_list)
      ~post_of_entry:(fun post_terms ->
        remove_terms cache post_terms common_post_terms_for_group
        |> term_and_list)
  in
  let combined_inner_implications =
    common_post_implications ~pre_terms:residual_pre_snapshot_terms
    @ implication_terms combined_grouped_post_preconditions
  in
  let combined_implications = wrap_common_pre combined_inner_implications in
  let combined_candidate =
    candidate cache ~kind:Boundary.Pre_and_post_common
      ~body:(term_and_list combined_implications)
      ~distinct_terms:
        (common_post_terms_for_group
        @ List.map snd combined_grouped_post_preconditions)
      ~implications:combined_implications
  in
  let selected =
    [ post_factored_candidate; pre_factored_candidate; combined_candidate ]
    |> List.fold_left
         (fun best candidate ->
           if candidate.candidate_body_bytes < best.candidate_body_bytes
           then candidate
           else best)
         original_candidate
  in
  let pre_text_bytes = term_size cache pre_term in
  let post_text_bytes = selected.candidate_body_bytes in
  let candidate_costs =
    Boundary.{
      original_estimated_cost =
        estimated_candidate_cost ~pre_text_bytes original_candidate;
      post_common_estimated_cost =
        estimated_candidate_cost ~pre_text_bytes post_factored_candidate;
      pre_common_estimated_cost =
        estimated_candidate_cost ~pre_text_bytes pre_factored_candidate;
      pre_and_post_common_estimated_cost =
        estimated_candidate_cost ~pre_text_bytes combined_candidate;
    }
  in
  {
    proof_terms = Boundary.{ pre_term; post_body = selected.candidate_body };
    profile =
      Boundary.{
        distinct_pre_count = unique_term_count cache pre_terms;
        distinct_post_count = selected.candidate_distinct_post_count;
        post_implication_count = selected.candidate_post_implication_count;
        pre_text_bytes;
        post_text_bytes;
        estimated_cost = pre_text_bytes + post_text_bytes;
        factor_kind = selected.candidate_kind;
        factor_candidate_costs = candidate_costs;
      };
  }
