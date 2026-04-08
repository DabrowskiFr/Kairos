(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
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

(** Organizes exported kernel clauses into Why3 contract fragments. *)

type transition_clauses = {
  transition_requires_pre_terms : (Why3.Ptree.term * string) list;
  transition_requires_pre : Why3.Ptree.term list;
  post_contract_terms : Why3.Ptree.term list;
  pure_post : Why3.Ptree.term list;
  post_terms : (Why3.Ptree.term * string) list;
  post_terms_vcid : (Why3.Ptree.term * string) list;
}

type link_contracts = {
  link_terms_pre : Why3.Ptree.term list;
  link_terms_post : Why3.Ptree.term list;
  link_invariants : Why3.Ptree.term list;
}

val compute_transition_contracts :
  env:Why_term_support.env ->
  product_transitions:Why_runtime_view.runtime_product_transition_view list ->
  post_contract_user:Why3.Ptree.term list ->
  transition_clauses

val compute_link_contracts :
  env:Why_term_support.env ->
  runtime:Why_runtime_view.t ->
  hexpr_needs_old:(Ast.hexpr -> bool) ->
  link_contracts
