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

open Ast
open Fo_specs
open Fo_time

let user_contracts_coherency (n : Ast.node) : Ast.node =
  (* Coherency rule: - for each transition t: conj(ensures t) => shifted(requires of transitions
     from t.dst) - for initial successors (from init_state): true => requires where "shifted"
     accounts for input-time alignment. *)
  let is_input = Ast_utils.is_input_of_node n in
  let transitions_from_state = Ast_utils.transitions_from_state_fn n in
  let transition_requires (t : transition) = Ast_provenance.values t.requires in
  let transition_ensures (t : transition) = Ast_provenance.values t.ensures in
  let shift_req f = shift_fo_backward_inputs ~is_input f in
  let coherency_goals_from_transition (t : transition) =
    let ens_conj = Option.value (conj_fo (transition_ensures t)) ~default:FTrue in
    let succ_transitions = transitions_from_state t.dst |> List.rev in
    List.concat_map
      (fun succ_t ->
        List.map (fun r -> FImp (ens_conj, shift_req r)) (transition_requires succ_t))
      succ_transitions
  in
  (* Initial-step coherency: transitions leaving [init_state] have an implicit predecessor (boot),
     so their requires must hold directly at the initial step. *)
  let initial_coherency_goals =
    Ast_utils.requires_from_state_fn n n.init_state
    |> List.map (fun r -> FImp (FTrue, shift_req r))
  in
  let new_goals =
    List.concat_map coherency_goals_from_transition n.trans @ initial_coherency_goals
  in
  Ast_utils.add_new_coherency_goals n new_goals
