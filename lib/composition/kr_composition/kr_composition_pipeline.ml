module Contract = Kr_engine.Kr_engine_contract
module Flow = Internal.Wiring

type config = Contract.config
type error = Contract.error

let default_proof_jobs = Kr_runtime_ports.default_proof_jobs
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
    ~proof_optimizations:Kr_engine.Kr_engine_pipeline_config.default_proof_optimizations ~input_file

let normalized_program_with_options ~proof_optimizations ~input_file =
  Flow.normalized_program ~proof_optimizations ~input_file

let ir_pretty_dump_with_options ~proof_optimizations ~input_file =
  Flow.ir_pretty_dump ~proof_optimizations ~input_file

let run = Flow.run

let run_with_callbacks ~should_cancel config ~on_outputs_ready
    ~on_goals_ready ~on_goal_done =
  Flow.run_with_callbacks ~should_cancel config ~on_outputs_ready
    ~on_goals_ready ~on_goal_done
