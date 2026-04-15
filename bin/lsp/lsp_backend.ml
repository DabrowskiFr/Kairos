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

module Usecases = Verification_flow_usecases.Make (Kairos_usecase_wiring.Ports)

let map_error = Pipeline_types.error_to_string

let with_engine (engine : Engine_service.engine) (k : unit -> ('a, string) result) :
    ('a, string) result =
  match Engine_service.normalize engine with
  | Engine_service.Default -> k ()

let pipeline_config_of_protocol (cfg : Lsp_protocol.config) : Pipeline_types.config =
  {
    input_file = cfg.input_file;
    wp_only = cfg.wp_only;
    smoke_tests = cfg.smoke_tests;
    timeout_s = cfg.timeout_s;
    compute_proof_diagnostics = cfg.compute_proof_diagnostics;
    prove = cfg.prove;
    generate_vc_text = cfg.generate_vc_text;
    generate_smt_text = cfg.generate_smt_text;
    generate_dot_png = cfg.generate_dot_png;
  }

let instrumentation_pass (req : Lsp_protocol.instrumentation_pass_request) =
  let engine =
    Option.value (Engine_service.engine_of_string req.engine)
      ~default:Engine_service.Default
  in
  with_engine engine (fun () ->
      match Usecases.instrumentation_pass ~generate_png:req.generate_png ~input_file:req.input_file with
      | Ok out -> Ok (Lsp_app.map_automata out)
      | Error e -> Error (map_error e))

let why_pass (req : Lsp_protocol.why_pass_request) =
  let engine =
    Option.value (Engine_service.engine_of_string req.engine)
      ~default:Engine_service.Default
  in
  with_engine engine (fun () ->
      match Usecases.why_pass ~input_file:req.input_file with
      | Ok out -> Ok (Lsp_app.map_why out)
      | Error e -> Error (map_error e))

let obligations_pass (req : Lsp_protocol.obligations_pass_request) =
  let engine =
    Option.value (Engine_service.engine_of_string req.engine)
      ~default:Engine_service.Default
  in
  with_engine engine (fun () ->
      match Usecases.obligations_pass ~input_file:req.input_file with
      | Ok out -> Ok (Lsp_app.map_oblig out)
      | Error e -> Error (map_error e))

let read_or_compile_kobj ~(input_file : string) =
  if Filename.check_suffix input_file ".kobj" then
    match Kairos_object.read_file ~path:input_file with
    | Ok obj -> Ok obj
    | Error msg -> Error (Pipeline_types.Flow_error msg)
  else Kairos_usecase_wiring.compile_object ~input_file

let kobj_summary (req : Lsp_protocol.kobj_summary_request) =
  let engine =
    Option.value (Engine_service.engine_of_string req.engine)
      ~default:Engine_service.Default
  in
  with_engine engine (fun () ->
      match read_or_compile_kobj ~input_file:req.input_file with
      | Ok obj -> Ok (Kairos_object.render_summary obj)
      | Error e -> Error (map_error e))

let kobj_clauses (req : Lsp_protocol.kobj_summary_request) =
  let engine =
    Option.value (Engine_service.engine_of_string req.engine)
      ~default:Engine_service.Default
  in
  with_engine engine (fun () ->
      match read_or_compile_kobj ~input_file:req.input_file with
      | Ok obj -> Ok (Kairos_object.render_clauses obj)
      | Error e -> Error (map_error e))

let kobj_product (req : Lsp_protocol.kobj_summary_request) =
  let engine =
    Option.value (Engine_service.engine_of_string req.engine)
      ~default:Engine_service.Default
  in
  with_engine engine (fun () ->
      match read_or_compile_kobj ~input_file:req.input_file with
      | Ok obj -> Ok (Kairos_object.render_product obj)
      | Error e -> Error (map_error e))

let kobj_contracts (req : Lsp_protocol.kobj_summary_request) =
  let engine =
    Option.value (Engine_service.engine_of_string req.engine)
      ~default:Engine_service.Default
  in
  with_engine engine (fun () ->
      match read_or_compile_kobj ~input_file:req.input_file with
      | Ok obj -> Ok (Kairos_object.render_product_summaries obj)
      | Error e -> Error (map_error e))

let normalized_program (req : Lsp_protocol.kobj_summary_request) =
  let engine =
    Option.value (Engine_service.engine_of_string req.engine)
      ~default:Engine_service.Default
  in
  with_engine engine (fun () ->
      match Usecases.normalized_program ~input_file:req.input_file with
      | Ok text -> Ok text
      | Error e -> Error (map_error e))

let ir_pretty_dump (req : Lsp_protocol.kobj_summary_request) =
  let engine =
    Option.value (Engine_service.engine_of_string req.engine)
      ~default:Engine_service.Default
  in
  with_engine engine (fun () ->
      match Usecases.ir_pretty_dump ~input_file:req.input_file with
      | Ok text -> Ok text
      | Error e -> Error (map_error e))

let dot_png_from_text (req : Lsp_protocol.dot_png_from_text_request) =
  Graphviz_render.dot_png_from_text req.dot_text

let run ~engine (cfg : Lsp_protocol.config) =
  with_engine engine (fun () ->
      match Usecases.run (pipeline_config_of_protocol cfg) with
      | Ok out -> Ok (Lsp_app.map_outputs out)
      | Error e -> Error (map_error e))

let run_with_callbacks ~engine ~should_cancel (cfg : Lsp_protocol.config)
    ~on_outputs_ready ~on_goals_ready ~on_goal_done =
  with_engine engine (fun () ->
      match
        Usecases.run_with_callbacks ~should_cancel (pipeline_config_of_protocol cfg)
          ~on_outputs_ready:(fun out -> on_outputs_ready (Lsp_app.map_outputs out))
          ~on_goals_ready ~on_goal_done
      with
      | Ok out -> Ok (Lsp_app.map_outputs out)
      | Error e -> Error (map_error e))
