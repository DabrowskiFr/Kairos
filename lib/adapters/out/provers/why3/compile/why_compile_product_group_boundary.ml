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

type t = {
  proof_terms : proof_terms;
  profile : profile;
}

let make proof_terms profile = { proof_terms; profile }

let proof_terms t = t.proof_terms

let profile t = t.profile

let factor_kind_name = function
  | Original -> "original"
  | Post_common -> "post_common"
  | Pre_common -> "pre_common"
  | Pre_and_post_common -> "pre_and_post_common"
