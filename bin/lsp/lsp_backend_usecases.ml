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
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *---------------------------------------------------------------------------*)

module Usecases = Verification_flow_usecases.Make (Kairos_usecase_wiring.Ports)

let map_error = Pipeline_types.error_to_string

let with_engine
    (engine : Engine_service.engine)
    (k : unit -> ('a, string) result) :
    ('a, string) result =
  match Engine_service.normalize engine with Engine_service.Default -> k ()

let engine_of_string s =
  Option.value (Engine_service.engine_of_string s)
    ~default:Engine_service.Default

let instrumentation_pass (req : Lsp_protocol.instrumentation_pass_request) =
  with_engine (engine_of_string req.engine) (fun () ->
      match
        Usecases.instrumentation_pass ~generate_png:req.generate_png
          ~input_file:req.input_file
      with
      | Ok out -> Ok (Lsp_pipeline_mapper.map_automata out)
      | Error e -> Error (map_error e))

let why_pass (req : Lsp_protocol.why_pass_request) =
  with_engine (engine_of_string req.engine) (fun () ->
      match
        Usecases.why_pass
          ~proof_encoding:Pipeline_types.default_proof_encoding
          ~proof_optimizations:Pipeline_types.default_proof_optimizations
          ~input_file:req.input_file
      with
      | Ok out -> Ok (Lsp_pipeline_mapper.map_why out)
      | Error e -> Error (map_error e))

let obligations_pass (req : Lsp_protocol.obligations_pass_request) =
  with_engine (engine_of_string req.engine) (fun () ->
      match
        Usecases.obligations_pass
          ~proof_encoding:Pipeline_types.default_proof_encoding
          ~proof_optimizations:Pipeline_types.default_proof_optimizations
          ~input_file:req.input_file
      with
      | Ok out -> Ok (Lsp_pipeline_mapper.map_oblig out)
      | Error e -> Error (map_error e))

let normalized_program (req : Lsp_protocol.text_dump_request) =
  with_engine (engine_of_string req.engine) (fun () ->
      match
        Usecases.normalized_program
          ~proof_encoding:Pipeline_types.default_proof_encoding
          ~proof_optimizations:Pipeline_types.default_proof_optimizations
          ~input_file:req.input_file
      with
      | Ok text -> Ok text
      | Error e -> Error (map_error e))

let ir_pretty_dump (req : Lsp_protocol.text_dump_request) =
  with_engine (engine_of_string req.engine) (fun () ->
      match
        Usecases.ir_pretty_dump
          ~proof_encoding:Pipeline_types.default_proof_encoding
          ~proof_optimizations:Pipeline_types.default_proof_optimizations
          ~input_file:req.input_file
      with
      | Ok text -> Ok text
      | Error e -> Error (map_error e))

let run ~engine (cfg : Lsp_protocol.config) =
  with_engine engine (fun () ->
      match Usecases.run (Lsp_backend_config.pipeline_config_of_protocol cfg) with
      | Ok out -> Ok (Lsp_pipeline_mapper.map_outputs out)
      | Error e -> Error (map_error e))

let run_with_callbacks ~engine ~should_cancel
    (cfg : Lsp_protocol.config)
    ~on_outputs_ready ~on_goals_ready ~on_goal_done =
  with_engine engine (fun () ->
      match
        Usecases.run_with_callbacks ~should_cancel
          (Lsp_backend_config.pipeline_config_of_protocol cfg)
          ~on_outputs_ready:(fun out ->
            on_outputs_ready (Lsp_pipeline_mapper.map_outputs out))
          ~on_goals_ready ~on_goal_done
      with
      | Ok out -> Ok (Lsp_pipeline_mapper.map_outputs out)
      | Error e -> Error (map_error e))
