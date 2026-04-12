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

let stage_parse_info_of_frontend (info : Parse_info.t) : Stage_info.parse_info =
  {
    source_path = info.source_path;
    text_hash = info.text_hash;
    parse_errors =
      List.map
        (fun (e : Parse_info.parse_error) ->
          ({ Stage_info.loc = e.loc; message = e.message } : Stage_info.parse_error))
        info.parse_errors;
    warnings = info.warnings;
  }

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
        (Pipeline_types.Stage_error
           (Printf.sprintf
              "Calls are not supported in this Kairos version (node '%s')."
              n.semantics.sem_nname))

let build_ast_with_info ~input_file () :
    (Pipeline_types.ast_stages * Pipeline_types.stage_infos, Pipeline_types.error)
    result =
  try
    let source, parse_info_front = Parse_file.parse_source_file_with_info input_file in
    let parse_info = stage_parse_info_of_frontend parse_info_front in
    let p_parsed = source.nodes in
    match reject_calls p_parsed with
    | Error _ as err -> err
    | Ok () ->
    let p_automaton, automata, automata_info =
      Automata_pass.Pass.run_with_info p_parsed ()
    in
    match Orchestration.run_with_metrics p_automaton automata with
    | Error msg -> Error (Pipeline_types.Stage_error msg)
    | Ok (ir_program, run_metrics) -> (
        External_timing.record_product ~elapsed_s:run_metrics.product_s;
        External_timing.record_canonical ~elapsed_s:run_metrics.canonical_s;
        let p_contracts = ir_program.nodes in
        let p_instrumentation = ir_program.nodes in
        let formulas_info : Stage_info.formulas_info = { warnings = [] }
        in
        match
          Instrumentation_info_builder.instrumentation_info_of_ir ~automata
            ~source_program:p_automaton ir_program
        with
        | Error msg -> Error (Pipeline_types.Stage_error msg)
        | Ok instrumentation_info ->
        let asts : Pipeline_types.ast_stages =
          {
            source;
            parsed = p_parsed;
            automata_generation = p_automaton;
            automata;
            contracts = p_contracts;
            instrumentation = p_instrumentation;
          }
        in
        let infos : Pipeline_types.stage_infos =
          {
            parse = Some parse_info;
            automata_generation = Some automata_info;
            contracts = Some formulas_info;
              instrumentation = Some instrumentation_info;
            }
        in
        Ok (asts, infos))
  with exn -> Error (Pipeline_types.Stage_error (Printexc.to_string exn))

let compile_object ~input_file : (Kairos_object.t, Pipeline_types.error) result =
  match build_ast_with_info ~input_file () with
  | Error _ as err -> err
  | Ok (asts, infos) ->
      let parse_info = Option.value infos.parse ~default:Stage_info.empty_parse_info in
      let instrumentation_info =
        Option.value infos.instrumentation ~default:Stage_info.empty_instrumentation_info
      in
      Kairos_object.build ~source_path:input_file ~source_hash:parse_info.text_hash
        ~imports:(Source_file.imported_paths asts.source) ~program:asts.parsed
        ~runtime_program:asts.automata_generation
        ~kernel_ir_nodes:instrumentation_info.kernel_ir_nodes
      |> Result.map_error (fun msg -> Pipeline_types.Stage_error msg)
