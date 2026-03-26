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

(** Builds readable labels for Why3 contract pre/post obligations. *)

(* {1 Contract Labels} *)

type label_context = {
  kernel_first : bool;
  pre : Why3.Ptree.term list;
  post : Why3.Ptree.term list;
  transition_requires_pre : Why3.Ptree.term list;
  transition_requires_pre_terms : (Why3.Ptree.term * string) list;
  link_terms_pre : Why3.Ptree.term list;
  link_terms_post : Why3.Ptree.term list;
  link_invariants : Why3.Ptree.term list;
  post_contract_user : Why3.Ptree.term list;
  instance_invariants : Why3.Ptree.term list;
}
(* Context used to generate labels from contract terms. *)

val build_labels : label_context -> string list * string list
(* Build pre/post labels for UI and proof traces. *)
