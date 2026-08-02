module Contract = Kairos_engine.Api.Contract
module Flow = Wiring
module Frontend = Kairos_lang.Frontend
module Source_services = Kairos_lang.Source_services

type config = Contract.config
type error = Contract.error

type source_diagnostic = Source_services.source_diagnostic = {
  line : int;
  column : int;
  severity : int;
  source : string;
  message : string;
}

type semantic_symbols = Source_services.semantic_symbols = {
  all : string list;
  nodes : string list;
  states : string list;
  variables : string list;
}

type frontend_summary = {
  node_count : int;
  assume_count : int;
  guarantee_count : int;
}

type generated_file = Kairos_engine.Api.generated_file = {
  file_name : string;
  contents : string;
}

let default_proof_jobs = Kairos_runtime_ports.default_proof_jobs
let error_to_string = Contract.error_to_string

let make_config ~input_file ~wp_only ~timeout_s
    ~compute_proof_diagnostics ~prove ?proof_jobs
    ?(dump_failed_smt = false) ?(collect_ir_metrics = false)
    ?proof_progress_path ?(stop_on_first_nonvalid = false)
    ?(proof_optimizations = Contract.default_proof_optimizations)
    ~generate_why_text ~generate_vc_text ~generate_smt_text
    ~generate_dot_png () =
  {
    Contract.input_file;
    wp_only;
    timeout_s;
    compute_proof_diagnostics;
    prove;
    proof_jobs = Option.value proof_jobs ~default:(default_proof_jobs ());
    generate_why_text;
    generate_vc_text;
    generate_smt_text;
    generate_dot_png;
    dump_failed_smt;
    collect_ir_metrics;
    proof_progress_path;
    stop_on_first_nonvalid;
    proof_optimizations;
  }

let instrumentation_pass ~generate_png ~input_file =
  Flow.instrumentation_pass ~generate_png ~input_file

let why_pass ~input_file =
  Flow.why_pass
    ~proof_optimizations:Contract.default_proof_optimizations
    ~input_file

let why_pass_with_options ~proof_optimizations ~input_file =
  Flow.why_pass ~proof_optimizations ~input_file

let obligations_pass ~input_file =
  Flow.obligations_pass
    ~proof_optimizations:Contract.default_proof_optimizations ~input_file

let obligations_pass_with_options ~proof_optimizations ~input_file =
  Flow.obligations_pass ~proof_optimizations ~input_file

let cost_report ~proof_optimizations ~input_file =
  Flow.cost_report ~proof_optimizations ~input_file

let normalized_program ~input_file =
  Flow.normalized_program
    ~proof_optimizations:Contract.default_proof_optimizations ~input_file

let ir_pretty_dump ~input_file =
  Flow.ir_pretty_dump
    ~proof_optimizations:Kairos_engine.Pipeline_config.default_proof_optimizations ~input_file

let normalized_program_with_options ~proof_optimizations ~input_file =
  Flow.normalized_program ~proof_optimizations ~input_file

let ir_pretty_dump_with_options ~proof_optimizations ~input_file =
  Flow.ir_pretty_dump ~proof_optimizations ~input_file

let run = Flow.run

let run_with_callbacks ~should_cancel config ~on_outputs_ready
    ~on_goals_ready ~on_goal_done =
  Flow.run_with_callbacks ~should_cancel config ~on_outputs_ready
    ~on_goals_ready ~on_goal_done

let source_diagnostics = Source_services.diagnostics
let semantic_symbols = Source_services.semantic_symbols

let surface_dump ~input_file =
  Source_services.surface_dump ~input_file
  |> Result.map_error Flow.error_of_frontend

let elaborated_dump ~input_file =
  Source_services.elaborated_dump ~input_file
  |> Result.map_error Flow.error_of_frontend

let frontend_summary ~input_file =
  match Frontend.parse_input ~input_file with
  | Error error -> Error (Flow.error_of_frontend error)
  | Ok frontend ->
      let nodes = frontend.Frontend.verification_model in
      let count_contracts select =
        nodes
        |> List.map (fun (node : Verification_model.node_model) ->
               List.length (select node))
        |> List.fold_left ( + ) 0
      in
      Ok
        {
          node_count = List.length nodes;
          assume_count = count_contracts (fun node -> node.assumes);
          guarantee_count = count_contracts (fun node -> node.guarantees);
        }

let generate_c = Flow.generate_c
