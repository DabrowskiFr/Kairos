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

(** Canonical construction of proof terms for one helper group.

    Common preconditions are factored once around the residual implications.
    This is the single representation used for grouped helpers. *)

open Why_compile_ptree_helpers
open Why_compile_expr

let pre_vars_name = "__pre_vars"
let post_vars_name = "__post_vars"

type entry = int * Step_contract_projection.step_contract

type t = {
  pre_term : Why3.Ptree.term;
  pre_inputs : used_inputs;
  post_body : Why3.Ptree.term;
  post_inputs : used_inputs;
}

type entry_terms = {
  pre_terms : Why3.Ptree.term list;
  post_terms : Why3.Ptree.term list;
}

let common_terms terms_by_entry =
  match terms_by_entry with
  | [] -> []
  | first :: rest ->
      List.filter
        (fun term -> List.for_all (fun terms -> List.mem term terms) rest)
        first

let remove_terms terms removed =
  List.filter (fun term -> not (List.mem term removed)) terms

let grouped_post_preconditions entries ~pre_of_entry =
  let groups = Hashtbl.create 16 in
  let order = ref [] in
  List.iter
    (fun { pre_terms; post_terms } ->
      let pre = pre_of_entry pre_terms in
      let post = term_and_list post_terms in
      if not (Hashtbl.mem groups post) then order := post :: !order;
      let previous = Hashtbl.find_opt groups post |> Option.value ~default:[] in
      Hashtbl.replace groups post (pre :: previous))
    entries;
  List.rev !order
  |> List.map (fun post ->
         let pres = Hashtbl.find groups post |> List.rev in
         (term_or_list pres, post))

let implication_terms grouped =
  List.filter_map
    (fun (pre, post) ->
      match (post : Why3.Ptree.term).Why3.Ptree.term_desc with
      | Why3.Ptree.Ttrue -> None
      | _ -> Some (term_implies pre post))
    grouped

let factor_common_preconditions entries =
  let common_pre =
    entries |> List.map (fun entry -> entry.pre_terms) |> common_terms
  in
  let residual_pre pre_terms =
    remove_terms pre_terms common_pre |> term_and_list
  in
  let residual_implications =
    grouped_post_preconditions entries ~pre_of_entry:residual_pre
    |> implication_terms
  in
  match common_pre with
  | [] -> term_and_list residual_implications
  | terms ->
      term_implies (term_and_list terms) (term_and_list residual_implications)

let build ~(env : Why_compile_expr.env) ~step_pre_terms_with_rec
    ~step_post_terms_with_rec (entries : entry list) =
  let pre_term, pre_inputs =
    collect_used_inputs env (fun env ->
        entries
        |> List.map (fun (_i, sc) ->
               step_pre_terms_with_rec env env.rec_name sc |> term_and_list)
        |> term_or_list)
  in
  let post_body, post_inputs =
    collect_used_inputs env (fun env ->
        List.map
          (fun (_i, sc) ->
            {
              pre_terms = step_pre_terms_with_rec env pre_vars_name sc;
              post_terms = step_post_terms_with_rec env post_vars_name sc;
            })
          entries
        |> factor_common_preconditions)
  in
  { pre_term; pre_inputs; post_body; post_inputs }
