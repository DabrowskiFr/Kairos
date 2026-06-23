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

open Why_compile_expr
open Why_compile_ptree_helpers

type entry =
  int * Why_contracts.step_contract_info * Why_runtime_view.runtime_transition_view

type grouped_terms = {
  pre_term : Why3.Ptree.term;
  post_body : Why3.Ptree.term;
  distinct_pre_count : int;
  distinct_post_count : int;
  post_implication_count : int;
  pre_text_bytes : int;
  post_text_bytes : int;
  estimated_cost : int;
}

type profile =
  entry * string * int * string * int * string * int

let unique_term_count terms =
  terms
  |> List.map string_of_term
  |> List.sort_uniq String.compare
  |> List.length

let grouped_kernel_terms ~(env : Why_compile_expr.env) ~(pre_vars_name : string)
    ~(post_vars_name : string) ~step_pre_terms_with_rec ~step_post_terms_with_rec
    (entries : entry list) =
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
           let post = step_post_terms_with_rec post_vars_name sc |> term_and_list in
           if not (Hashtbl.mem groups post) then order := post :: !order;
           let previous = Hashtbl.find_opt groups post |> Option.value ~default:[] in
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
  let post_terms = grouped_post_preconditions |> List.map (fun (_pre, post) -> post) in
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

let group_entry_profile ~(env : Why_compile_expr.env) ~(pre_vars_name : string)
    ~(post_vars_name : string) ~step_pre_terms_with_rec ~step_post_terms_with_rec
    (((_i, sc, _t) as entry) : entry) : profile =
  let pre_current = step_pre_terms_with_rec env.rec_name sc |> term_and_list in
  let pre_snapshot = step_pre_terms_with_rec pre_vars_name sc |> term_and_list in
  let post_snapshot = step_post_terms_with_rec post_vars_name sc |> term_and_list in
  let pre_current_s = string_of_term pre_current in
  let pre_snapshot_s = string_of_term pre_snapshot in
  let post_snapshot_s = string_of_term post_snapshot in
  ( entry,
    pre_current_s,
    String.length pre_current_s,
    pre_snapshot_s,
    String.length pre_snapshot_s,
    post_snapshot_s,
    String.length post_snapshot_s )

let profile_entry
    (entry, _pre_current_s, _pre_current_bytes, _pre_snapshot_s,
     _pre_snapshot_bytes, _post_snapshot_s, _post_snapshot_bytes) =
  entry

let profiled_group_cost profiles =
  let pre_bytes =
    profiles
    |> List.fold_left
         (fun acc
              (_entry, _pre_current_s, pre_current_bytes, _pre_snapshot_s,
               _pre_snapshot_bytes, _post_snapshot_s, _post_snapshot_bytes) ->
           acc + pre_current_bytes)
         0
  in
  let post_groups = Hashtbl.create 16 in
  profiles
  |> List.iter
       (fun (_entry, _pre_current_s, _pre_current_bytes, _pre_snapshot_s,
            pre_snapshot_bytes, post_snapshot_s, post_snapshot_bytes) ->
         let previous_pre_bytes, previous_post_bytes =
           Hashtbl.find_opt post_groups post_snapshot_s
           |> Option.value ~default:(0, post_snapshot_bytes)
         in
         Hashtbl.replace post_groups post_snapshot_s
           (previous_pre_bytes + pre_snapshot_bytes, previous_post_bytes));
  pre_bytes
  + (post_groups
    |> Hashtbl.to_seq_values
    |> Seq.fold_left
         (fun acc (pre_snapshot_bytes, post_snapshot_bytes) ->
           acc + pre_snapshot_bytes + post_snapshot_bytes)
         0)

let split_group_by_cost ~(max_cost : int) ~(env : Why_compile_expr.env)
    ~(pre_vars_name : string) ~(post_vars_name : string) ~step_pre_terms_with_rec
    ~step_post_terms_with_rec (entries : entry list) =
  if max_cost <= 0 then [ entries ]
  else
    let profiles =
      List.map
        (group_entry_profile ~env ~pre_vars_name ~post_vars_name
           ~step_pre_terms_with_rec ~step_post_terms_with_rec)
        entries
    in
    let rec loop chunks current_rev rest =
      match rest with
      | [] ->
          let chunks =
            match current_rev with
            | [] -> chunks
            | _ -> (List.rev current_rev |> List.map profile_entry) :: chunks
          in
          List.rev chunks
      | profile :: tail ->
          let candidate = List.rev (profile :: current_rev) in
          if current_rev <> [] && profiled_group_cost candidate > max_cost then
            let chunk = List.rev current_rev |> List.map profile_entry in
            loop (chunk :: chunks) [ profile ] tail
          else loop chunks (profile :: current_rev) tail
    in
    loop [] [] profiles

let group_kernel_helpers ~(env : Why_compile_expr.env) ~(pre_vars_name : string)
    ~(post_vars_name : string) ~(group_why3_product_steps : bool)
    ~(max_cost : int) ~(simplify_runtime_actions : bool)
    ~step_pre_terms_with_rec ~step_post_terms_with_rec ~build_individual
    ~build_grouped ~record_singleton_split_chunk step_contracts =
  let indexed_transitions =
    step_contracts
    |> List.mapi (fun i (sc : Why_contracts.step_contract_info) ->
           let t =
             Why_runtime_view.transition_of_product_step
               ~simplify_runtime_actions sc.step
           in
           (i, sc, t))
  in
  let groups = Hashtbl.create 128 in
  let order = ref [] in
  let group_key (_i, (sc : Why_contracts.step_contract_info), t) =
    (sc.step.step_class, t)
  in
  List.iter
    (fun entry ->
      let key = group_key entry in
      if not (Hashtbl.mem groups key) then order := key :: !order;
      let previous = Hashtbl.find_opt groups key |> Option.value ~default:[] in
      Hashtbl.replace groups key (entry :: previous))
    indexed_transitions;
  List.rev !order
  |> List.concat_map (fun key ->
         let entries = Hashtbl.find groups key |> List.rev in
         let group_is_safe =
           match entries with
           | [] -> false
           | (_i, (sc : Why_contracts.step_contract_info), _t) :: _ ->
               sc.step.step_class = Why_runtime_view.StepSafe
         in
         let groupable =
           group_why3_product_steps
           && List.length entries > 1
           && group_is_safe
           && List.for_all
                (fun (_i, (sc : Why_contracts.step_contract_info), _t) ->
                  sc.local_cuts = [])
                entries
         in
         if groupable then
           let chunks =
             split_group_by_cost ~max_cost ~env ~pre_vars_name ~post_vars_name
               ~step_pre_terms_with_rec ~step_post_terms_with_rec entries
           in
           let split_due_to_cost = List.length chunks > 1 in
           chunks
           |> List.concat_map (function
                | [] -> []
                | [ (i, sc, _t) as entry ] ->
                    record_singleton_split_chunk ~split_due_to_cost entry;
                    [ build_individual (i, sc) ]
                | chunk -> [ build_grouped ~split_due_to_cost chunk ])
         else
           entries
           |> List.map (fun (i, sc, _t) -> build_individual (i, sc)))
