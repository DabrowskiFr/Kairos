(*---------------------------------------------------------------------------
 * Tempo - synchronous runtime for OCaml
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

(** {1 Contract Diagnostics} *)

type label_context = {
  pre : Why3.Ptree.term list;
  post : Why3.Ptree.term list;
  transition_requires_pre : Why3.Ptree.term list;
  transition_requires_pre_terms : (Why3.Ptree.term * string) list;
  pre_contract_user_no_lemma : Why3.Ptree.term list;
  pre_lemma_terms : Why3.Ptree.term list;
  link_terms_pre : Why3.Ptree.term list;
  link_terms_post : Why3.Ptree.term list;
  instance_input_links_pre : Why3.Ptree.term list;
  pre_invf : Why3.Ptree.term list;
  first_step_init_link_pre : Why3.Ptree.term list;
  link_invariants : Why3.Ptree.term list;
  post_contract_user_no_lemma : Why3.Ptree.term list;
  post_lemma_terms : Why3.Ptree.term list;
  state_post_lemmas : Why3.Ptree.term list;
  state_post_lemmas_terms : (Why3.Ptree.term * string) list;
  instance_input_links_post : Why3.Ptree.term list;
  instance_invariants : Why3.Ptree.term list;
  post_invf : Why3.Ptree.term list;
  pre_k_links : Why3.Ptree.term list;
  result_term_opt : Why3.Ptree.term option;
}

(** Build pre/post labels for diagnostics and UI. *)
val build_labels : label_context -> string list * string list
