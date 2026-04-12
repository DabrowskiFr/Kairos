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

(** Instrumentation/automata artifact pass extracted from the v2 pipeline implementation. *)

let instrumentation_pass ~generate_png ~input_file =
  match Pipeline_build.build_ast_with_info ~input_file () with
  | Error _ as e -> e
  | Ok (snapshot : Pipeline_types.pipeline_snapshot) ->
      let asts = snapshot.asts in
      begin
        match Pipeline_artifact_bundle.build ~asts with
        | Error msg -> Error (Pipeline_types.Flow_error msg)
        | Ok artifacts ->
            Ok
              (Output_mapper.map_automata_outputs ~generate_png ~snapshot
                 ~artifacts)
      end

let compile_object ~input_file : (Kairos_object.t, Pipeline_types.error) result =
  match Pipeline_build.build_ast_with_info ~input_file () with
  | Error _ as err -> err
  | Ok (snapshot : Pipeline_types.pipeline_snapshot) ->
      let asts = snapshot.asts in
      let infos = snapshot.infos in
      begin
        match Pipeline_artifact_bundle.build ~asts with
        | Error msg -> Error (Pipeline_types.Flow_error msg)
        | Ok artifacts ->
            let parse_info =
              Option.value infos.parse ~default:Flow_info.empty_parse_info
            in
            Kairos_object.build ~source_path:input_file
              ~source_hash:parse_info.text_hash
              ~imports:(Source_file.imported_paths asts.source)
              ~program:asts.parsed ~runtime_program:asts.automata_generation
              ~kernel_ir_nodes:artifacts.kernel_ir_nodes
            |> Result.map_error (fun msg -> Pipeline_types.Flow_error msg)
      end
