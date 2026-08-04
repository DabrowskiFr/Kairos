module Frontend = Kr_lang.Kr_lang_frontend
module Usecases =
  Kr_engine.Use_cases.Make (Kr_runtime_ports.Ports)

let ( let* ) = Result.bind

let engine_diagnostic (diagnostic : Frontend.diagnostic) =
  { Kr_engine.Pipeline_error.loc = diagnostic.loc; message = diagnostic.message }

let error_of_frontend = function
  | Frontend.Parse_error diagnostic ->
      Kr_engine.Api.Contract.Parse_error
        (engine_diagnostic diagnostic)
  | Frontend.Elaboration_error diagnostic ->
      Kr_engine.Api.Contract.Elaboration_error
        (engine_diagnostic diagnostic)
  | Frontend.Type_error diagnostic ->
      Kr_engine.Api.Contract.Type_error
        (engine_diagnostic diagnostic)
  | Frontend.Well_formedness_error diagnostic ->
      Kr_engine.Api.Contract.Well_formedness_error
        (engine_diagnostic diagnostic)
  | Frontend.Io_error message -> Kr_engine.Api.Contract.Io_error message
  | Frontend.Internal_error message ->
      Kr_engine.Api.Contract.Internal_error message

let parse_input ~input_file =
  let* frontend =
    Frontend.parse_input ~input_file |> Result.map_error error_of_frontend
  in
  Ok
    (Kr_engine.Inbound_port.make_verification_input
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

let run (cfg : Kr_engine.Api.config) =
  with_input ~input_file:cfg.input_file (fun input -> Usecases.run ~input cfg)

let run_with_callbacks ~should_cancel
    (cfg : Kr_engine.Api.config) ~on_outputs_ready ~on_goals_ready
    ~on_goal_done =
  with_input ~input_file:cfg.input_file (fun input ->
      Usecases.run_with_callbacks ~should_cancel ~input cfg
        ~on_outputs_ready ~on_goals_ready ~on_goal_done)
