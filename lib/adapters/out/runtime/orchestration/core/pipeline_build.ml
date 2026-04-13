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

let ( let* ) = Result.bind

let rec stmt_contains_call (s : Ast.stmt) : bool =
  match s.stmt with
  | SCall _ -> true
  | SIf (_, then_branch, else_branch) ->
      List.exists stmt_contains_call then_branch || List.exists stmt_contains_call else_branch
  | SMatch (_, branches, default_branch) ->
      List.exists
        (fun (_ctor, body) -> List.exists stmt_contains_call body)
        branches
      || List.exists stmt_contains_call default_branch
  | SAssign _ | SSkip -> false

let transition_contains_call (t : Ast.transition) : bool =
  List.exists stmt_contains_call t.body

let node_uses_calls (n : Ast.node) : bool =
  n.semantics.sem_instances <> [] || List.exists transition_contains_call n.semantics.sem_trans

let reject_calls (program : Ast.program) : (unit, Pipeline_types.error) result =
  match List.find_opt node_uses_calls program with
  | None -> Ok ()
  | Some n ->
      Error
        (Pipeline_types.Flow_error
           (Printf.sprintf
              "Calls are not supported in this Kairos version (node '%s')."
              n.semantics.sem_nname))

let build_snapshot_from_frontend ~(frontend : Pipeline_types.frontend_payload) :
    (Pipeline_types.pipeline_snapshot, Pipeline_types.error)
    result =
  try
    let imports = frontend.imports in
    let parse_info = frontend.parse_info in
    let p_parsed = frontend.parsed in
    let p_model = frontend.verification_model in
    match reject_calls p_parsed with
    | Error _ as err -> err
    | Ok () ->
    let automata, automata_pass_info =
      Automata_generation.run p_model ~build_automaton:Spot_automaton_builder.build
    in
    let automata_info : Flow_info.automata_info =
      {
        residual_state_count = automata_pass_info.residual_state_count;
        residual_edge_count = automata_pass_info.residual_edge_count;
        warnings = automata_pass_info.warnings;
      }
    in
    let t_product = Unix.gettimeofday () in
    let p_summaries =
      match Orchestration.build_initial_ir ~automata p_model with
      | Error msg -> Error (Pipeline_types.Flow_error msg)
      | Ok summaries ->
          External_timing.record_product ~elapsed_s:(Unix.gettimeofday () -. t_product);
          Ok summaries
    in
    match p_summaries with
    | Error _ as err -> err
    | Ok p_summaries -> (
        let t_canonical = Unix.gettimeofday () in
        let ir_program = Orchestration.build_instrumented_ir p_summaries in
        External_timing.record_canonical ~elapsed_s:(Unix.gettimeofday () -. t_canonical);
        let p_instrumentation = ir_program.nodes in
        let summaries_info : Flow_info.summaries_info = { warnings = [] }
        in
        match
          Instrumentation_info_builder.instrumentation_info_of_ir ~automata
            ~source_program:p_parsed ~source_model:p_model ir_program
        with
        | Error msg -> Error (Pipeline_types.Flow_error msg)
        | Ok instrumentation_info ->
        let asts : Pipeline_types.ast_flow =
          {
            imports;
            parsed = p_parsed;
            verification_model = p_model;
            automata_generation = p_parsed;
            automata;
            summaries = p_summaries;
            instrumentation = p_instrumentation;
          }
        in
        let infos : Pipeline_types.flow_infos =
          {
            parse = Some parse_info;
            automata_generation = Some automata_info;
            summaries = Some summaries_info;
            instrumentation = Some instrumentation_info;
          }
        in
        let snapshot : Pipeline_types.pipeline_snapshot = { asts; infos } in
        Ok snapshot)
  with exn -> Error (Pipeline_types.Flow_error (Printexc.to_string exn))
