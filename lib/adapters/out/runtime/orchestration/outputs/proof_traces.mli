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

(** Construction of public proof traces from proof results and artifacts. *)

val needed : Pipeline_config.config -> bool

val build_from_execution :
  goals:
    Kairos_why3_contract.Why3_contract.goal_descriptor list ->
  manifest:Why_pipeline.compilation_manifest ->
  goal_results:Proof_goal_results.t list ->
  vc_ids_ordered:int list ->
  vc_spans_ordered:Pipeline_proof_types.text_span list ->
  smt_spans_ordered:Pipeline_proof_types.text_span list ->
  Pipeline_proof_types.proof_trace list

val build_fast :
  manifest:Why_pipeline.compilation_manifest ->
  Proof_goal_results.t list ->
  Pipeline_proof_types.proof_trace list

val goals_of_proof_traces :
  Pipeline_proof_types.proof_trace list -> Pipeline_proof_types.goal_info list

val goals_of_goal_results :
  Proof_goal_results.t list -> Pipeline_proof_types.goal_info list
