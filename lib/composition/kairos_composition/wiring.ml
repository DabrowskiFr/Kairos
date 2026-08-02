module Frontend = Kairos_lang.Frontend
module Usecases =
  Kairos_engine.Inbound.Make (Kairos_runtime_ports.Ports)

let ( let* ) = Result.bind

let error_of_frontend = function
  | Frontend.Parse_error message ->
      Kairos_engine.Api.Contract.Parse_error message
  | Frontend.Elaboration_error message ->
      Kairos_engine.Api.Contract.Elaboration_error message
  | Frontend.Type_error message ->
      Kairos_engine.Api.Contract.Type_error message
  | Frontend.Well_formedness_error message ->
      Kairos_engine.Api.Contract.Well_formedness_error message
  | Frontend.Io_error message -> Kairos_engine.Api.Contract.Io_error message
  | Frontend.Internal_error message ->
      Kairos_engine.Api.Contract.Internal_error message

let parse_input ~input_file =
  let* frontend =
    Frontend.parse_input ~input_file |> Result.map_error error_of_frontend
  in
  Ok
    (Kairos_engine.Outbound_ports.make_verification_input
       ~source_path:frontend.parse_info.source_path
       ~text_hash:frontend.parse_info.text_hash
       ~warnings:frontend.parse_info.warnings
       ~verification_model:frontend.verification_model)

let with_input ~input_file operation =
  let* input = parse_input ~input_file in
  operation input

let instrumentation_pass ~generate_png ~input_file =
  with_input ~input_file (fun input ->
      Usecases.instrumentation_pass ~generate_png ~input)

let why_pass ~proof_optimizations ~input_file =
  with_input ~input_file (fun input ->
      Usecases.why_pass ~proof_optimizations ~input)

let obligations_pass ~proof_optimizations ~input_file =
  with_input ~input_file (fun input ->
      Usecases.obligations_pass ~proof_optimizations ~input)

let cost_report ~proof_optimizations ~input_file =
  with_input ~input_file (fun input ->
      Usecases.cost_report ~proof_optimizations ~input)

let normalized_program ~proof_optimizations ~input_file =
  with_input ~input_file (fun input ->
      Usecases.normalized_program ~proof_optimizations ~input)

let ir_pretty_dump ~proof_optimizations ~input_file =
  with_input ~input_file (fun input ->
      Usecases.ir_pretty_dump ~proof_optimizations ~input)

let generate_c ~input_file =
  with_input ~input_file (fun input -> Usecases.generate_c ~input)

let run (cfg : Kairos_engine.Api.config) =
  with_input ~input_file:cfg.input_file (fun input -> Usecases.run ~input cfg)

let run_with_callbacks ~should_cancel
    (cfg : Kairos_engine.Api.config) ~on_outputs_ready ~on_goals_ready
    ~on_goal_done =
  with_input ~input_file:cfg.input_file (fun input ->
      Usecases.run_with_callbacks ~should_cancel ~input cfg
        ~on_outputs_ready ~on_goals_ready ~on_goal_done)
