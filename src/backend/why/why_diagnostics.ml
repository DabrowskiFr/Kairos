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
  pre : Ptree.term list;
  post : Ptree.term list;
  transition_requires_pre : Ptree.term list;
  transition_requires_pre_terms : (Ptree.term * string) list;
  transition_post_terms : (Ptree.term * string) list;
  pre_contract_user_no_lemma : Ptree.term list;
  pre_lemma_terms : Ptree.term list;
  link_terms_pre : Ptree.term list;
  link_terms_post : Ptree.term list;
  instance_input_links_pre : Ptree.term list;
  pre_invf : Ptree.term list;
  first_step_init_link_pre : Ptree.term list;
  link_invariants : Ptree.term list;
  post_contract_user_no_lemma : Ptree.term list;
  post_lemma_terms : Ptree.term list;
  state_post_lemmas : Ptree.term list;
  state_post_lemmas_terms : (Ptree.term * string) list;
  instance_input_links_post : Ptree.term list;
  instance_invariants : Ptree.term list;
  post_invf : Ptree.term list;
  pre_k_links : Ptree.term list;
  result_term_opt : Ptree.term option;
}

let build_labels (ctx:label_context) : string list * string list =
  let pre_out = List.rev ctx.pre in
  let post_out = List.rev ctx.post in
  let group_terms_by_pre terms =
    List.filter (fun t -> List.mem t pre_out) terms
  in
  let group_terms_by_post terms =
    List.filter (fun t -> List.mem t post_out) terms
  in
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
      (fun t (compat, atom, user) ->
         let s = Support.string_of_term t in
         if contains_sub s "__mon_state" && contains_sub s "st" then
           (t :: compat, atom, user)
         else if contains_sub s "atom_" then
           (compat, t :: atom, user)
         else
           (compat, atom, t :: user))
      terms
      ([], [], [])
  in
  let compat_pre, atom_pre, user_pre = split_link_terms ctx.link_terms_pre in
  let compat_post, atom_post, user_post = split_link_terms ctx.link_terms_post in
  let pre_groups =
    [
      ("Transition requires", group_terms_by_pre ctx.transition_requires_pre);
      ("Contract requires", group_terms_by_pre ctx.pre_contract_user_no_lemma);
      ("Lemmas (pre)", group_terms_by_pre ctx.pre_lemma_terms);
      ("Atoms", group_terms_by_pre atom_pre);
      ("Compatibility", group_terms_by_pre compat_pre);
      ("User invariants", group_terms_by_pre user_pre);
      ("Instance links (pre)", group_terms_by_pre ctx.instance_input_links_pre);
      ("Monitor", group_terms_by_pre ctx.pre_invf);
      ("Initialization/first_step", group_terms_by_pre ctx.first_step_init_link_pre);
      ("Internal links", group_terms_by_pre ctx.link_invariants);
    ]
  in
  let post_groups =
    let base =
      [
        ("Transition lemmas", group_terms_by_post ctx.state_post_lemmas);
        ("Lemmas", group_terms_by_post ctx.post_lemma_terms);
        ("Contract ensures", group_terms_by_post ctx.post_contract_user_no_lemma);
        ("Atoms", group_terms_by_post atom_post);
        ("Compatibility", group_terms_by_post compat_post);
        ("User invariants", group_terms_by_post user_post);
        ("Instance links (post)", group_terms_by_post ctx.instance_input_links_post);
        ("Instance invariants", group_terms_by_post ctx.instance_invariants);
        ("Monitor", group_terms_by_post ctx.post_invf);
        ("pre_k history", group_terms_by_post ctx.pre_k_links);
        ("Internal links", group_terms_by_post ctx.link_invariants);
      ]
    in
    match ctx.result_term_opt with
    | None -> base
    | Some t -> base @ [("Result", group_terms_by_post [t])]
  in
  let fallback_label t =
    let s = Support.string_of_term t in
    if contains_sub s "__mon_state" then
      if contains_sub s "<>" || contains_sub s "!=" then
        Some "Bad state"
      else
        Some "Compatibility"
    else
      None
  in
  let rec term_has_old (t:Ptree.term) : bool =
    match t.term_desc with
    | Tapply (fn, _arg) ->
        begin match fn.term_desc with
        | Tident q -> Support.string_of_qid q = "old"
        | _ -> term_has_old fn
        end
    | Tbinop (a, _, b)
    | Tinnfix (a, _, b) -> term_has_old a || term_has_old b
    | Tnot a -> term_has_old a
    | Tidapp (_q, args) -> List.exists term_has_old args
    | Tif (c, t1, t2) -> term_has_old c || term_has_old t1 || term_has_old t2
    | Ttuple ts -> List.exists term_has_old ts
    | Tident _ | Tconst _ | Ttrue | Tfalse -> false
    | _ -> false
  in
  let label_for_term groups overrides t =
    match List.find_opt (fun (term, _) -> term = t) overrides with
    | Some (_, lbl) -> lbl
    | None ->
        match List.find_opt (fun (_lbl, terms) -> List.mem t terms) groups with
        | Some (lbl, _) -> lbl
        | None ->
            (match fallback_label t with
             | Some lbl -> lbl
             | None -> "Other")
  in
  let pre_labels =
    List.map (label_for_term pre_groups ctx.transition_requires_pre_terms) pre_out
  in
  let post_label_queue = Queue.create () in
  List.iter (fun (_t, lbl) -> Queue.add lbl post_label_queue) ctx.transition_post_terms;
  let lemma_label_for_term t =
    List.find_map
      (fun (term, lbl) -> if term = t then Some lbl else None)
      ctx.state_post_lemmas_terms
  in
  let label_for_post_term t =
    match lemma_label_for_term t with
    | Some lbl -> lbl
    | None when term_has_old t && not (Queue.is_empty post_label_queue) ->
        Queue.take post_label_queue
    | None ->
        label_for_term post_groups [] t
  in
  let post_labels = List.map label_for_post_term post_out in
  (pre_labels, post_labels)
