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

(** Typed boundary for grouped product-step backend data.

    [proof_terms] is the only view needed by Why3 helper emission. [profile] is
    backend diagnostic metadata and must not feed back into obligation
    construction. *)

type entry =
  int * Why_contracts.step_contract_info * Why_runtime_view.runtime_transition_view

type proof_terms = {
  pre_term : Why3.Ptree.term;
  post_body : Why3.Ptree.term;
}

type factor_kind =
  | Original
  | Post_common
  | Pre_common
  | Pre_and_post_common

type factor_candidate_costs = {
  original_estimated_cost : int;
  post_common_estimated_cost : int;
  pre_common_estimated_cost : int;
  pre_and_post_common_estimated_cost : int;
}

type profile = {
  distinct_pre_count : int;
  distinct_post_count : int;
  post_implication_count : int;
  pre_text_bytes : int;
  post_text_bytes : int;
  estimated_cost : int;
  factor_kind : factor_kind;
  factor_candidate_costs : factor_candidate_costs;
}

type t

val make : proof_terms -> profile -> t
val proof_terms : t -> proof_terms
val profile : t -> profile
val factor_kind_name : factor_kind -> string
