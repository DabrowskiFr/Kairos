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

[@@@ocaml.warning "-8-26-27-32-33"]

open Why3
open Ptree

type label_context = {
  kernel_first : bool;
  pre : Ptree.term list;
  post : Ptree.term list;
  transition_requires_pre : Ptree.term list;
  transition_requires_pre_terms : (Ptree.term * string) list;
  link_terms_pre : Ptree.term list;
  link_terms_post : Ptree.term list;
  link_invariants : Ptree.term list;
  post_contract_user : Ptree.term list;
  instance_invariants : Ptree.term list;
}

let build_labels (ctx : label_context) : string list * string list =
  let pre_out = List.rev ctx.pre in
  let post_out = List.rev ctx.post in
  let group_terms_by_pre terms = List.filter (fun t -> List.mem t pre_out) terms in
  let group_terms_by_post terms = List.filter (fun t -> List.mem t post_out) terms in
  let contains_sub s sub =
    let len_s = String.length s in
    let len_sub = String.length sub in
    let rec loop i =
      if i + len_sub > len_s then false
      else if String.sub s i len_sub = sub then true
      else loop (i + 1)
    in
    if len_sub = 0 then true else loop 0
  in
  let split_link_terms terms =
    List.fold_right
      (fun t (atom, user) ->
        let s = Support.string_of_term t in
        if contains_sub s "atom_" then (t :: atom, user) else (atom, t :: user))
      terms ([], [])
  in
  let atom_pre, user_pre = split_link_terms ctx.link_terms_pre in
  let atom_post, user_post = split_link_terms ctx.link_terms_post in
  let pre_groups =
    if ctx.kernel_first then
      [
        ("Transition requires", group_terms_by_pre ctx.transition_requires_pre);
        ("Internal links", group_terms_by_pre ctx.link_invariants);
      ]
    else
      [
        ("Transition requires", group_terms_by_pre ctx.transition_requires_pre);
        ("Atoms", group_terms_by_pre atom_pre);
        ("User invariants", group_terms_by_pre user_pre);
        ("Internal links", group_terms_by_pre ctx.link_invariants);
      ]
  in
  let post_groups =
    let base =
      if ctx.kernel_first then
        [ ("Internal links", group_terms_by_post ctx.link_invariants) ]
      else
        [
          ("User contract ensures", group_terms_by_post ctx.post_contract_user);
          ("Atoms", group_terms_by_post atom_post);
          ("User invariants", group_terms_by_post user_post);
          ("Instance invariants", group_terms_by_post ctx.instance_invariants);
          ("Internal links", group_terms_by_post ctx.link_invariants);
        ]
    in
    base
  in
  let label_for_term groups overrides t =
    match List.find_opt (fun (term, _) -> term = t) overrides with
    | Some (_, lbl) -> lbl
    | None -> (
        match List.find_opt (fun (_lbl, terms) -> List.mem t terms) groups with
        | Some (lbl, _) -> lbl
        | None -> "Other")
  in
  let pre_labels = List.map (label_for_term pre_groups ctx.transition_requires_pre_terms) pre_out in
  let post_labels = List.map (label_for_term post_groups []) post_out in
  (pre_labels, post_labels)
