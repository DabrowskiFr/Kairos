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

(** Source-program section of the pipeline cost report. *)

open Pipeline_cost_report_common
open Pipeline_cost_report_syntax

let source_node_json (node : Verification_model.node_model) =
  let assumes = node.assumes in
  let guarantees = node.guarantees in
  let transition_body_sizes =
    List.map
      (fun (step : Verification_model.program_step) ->
        sum_int (List.map stmt_size step.body_stmts))
      node.steps
  in
  let ltl_formulas = assumes @ guarantees in
  json_assoc
    [
      ("name", json_string node.node_name);
      ("input_count", json_int (List.length node.inputs));
      ("output_count", json_int (List.length node.outputs));
      ("local_count", json_int (List.length node.locals));
      ("ghost_count", json_int (List.length node.ghosts));
      ("state_count", json_int (List.length node.states));
      ("transition_count", json_int (List.length node.steps));
      ("assume_count", json_int (List.length assumes));
      ("guarantee_count", json_int (List.length guarantees));
      ("state_invariant_count", json_int (List.length node.state_invariants));
      ("total_transition_body_size", json_int (sum_int transition_body_sizes));
      ("max_transition_body_size", json_int (max_int transition_body_sizes));
      ("total_ltl_size", json_int (sum_int (List.map ltl_size ltl_formulas)));
      ("max_ltl_size", json_int (max_int (List.map ltl_size ltl_formulas)));
      ( "max_ltl_temporal_depth",
        json_int (max_int (List.map ltl_temporal_depth ltl_formulas)) );
      ( "max_ltl_pre_depth",
        json_int (max_int (List.map ltl_max_pre_depth ltl_formulas)) );
    ]

let source_json (snapshot : Runtime_snapshot.pipeline_snapshot) =
  let nodes = snapshot.asts.verification_model in
  json_assoc
    [
      ("node_count", json_int (List.length nodes));
      ("nodes", json_list source_node_json nodes);
    ]
