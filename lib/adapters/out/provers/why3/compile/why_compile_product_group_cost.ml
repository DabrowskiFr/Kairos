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

type entry = Why_compile_product_group_terms.entry

type context = {
  env : Why_compile_expr.env;
  pre_vars_name : string;
  post_vars_name : string;
  step_pre_terms_with_rec :
    string -> Why_contracts.step_contract_info -> Why3.Ptree.term list;
  step_post_terms_with_rec :
    string -> Why_contracts.step_contract_info -> Why3.Ptree.term list;
}

type profile =
  entry * string * int * string * int * string * int

let group_entry_profile ctx (((_i, sc, _t) as entry) : entry) : profile =
  let pre_current =
    ctx.step_pre_terms_with_rec ctx.env.rec_name sc |> term_and_list
  in
  let pre_snapshot =
    ctx.step_pre_terms_with_rec ctx.pre_vars_name sc |> term_and_list
  in
  let post_snapshot =
    ctx.step_post_terms_with_rec ctx.post_vars_name sc |> term_and_list
  in
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

let split_by_cost ctx ~(max_cost : int) (entries : entry list) =
  if max_cost <= 0 then [ entries ]
  else
    let profiles = List.map (group_entry_profile ctx) entries in
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
