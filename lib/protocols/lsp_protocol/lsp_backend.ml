let map_error = Pipeline_types.error_to_string

let pipeline_config_of_protocol (cfg : Lsp_protocol.config) : Pipeline_types.config =
  {
    input_file = cfg.input_file;
    prover = cfg.prover;
    prover_cmd = cfg.prover_cmd;
    wp_only = cfg.wp_only;
    smoke_tests = cfg.smoke_tests;
    timeout_s = cfg.timeout_s;
    selected_goal_index = cfg.selected_goal_index;
    compute_proof_diagnostics = cfg.compute_proof_diagnostics;
    prefix_fields = cfg.prefix_fields;
    prove = cfg.prove;
    generate_vc_text = cfg.generate_vc_text;
    generate_smt_text = cfg.generate_smt_text;
    generate_dot_png = cfg.generate_dot_png;
    disable_why3_optimizations = cfg.disable_why3_optimizations;
  }

let read_or_compile_kobj ~(engine : Engine_service.engine) ~(input_file : string) =
  if Filename.check_suffix input_file ".kobj" then
    Kairos_object.read_file ~path:input_file
  else
    match Engine_service.compile_object ~engine ~input_file with
    | Ok obj -> Ok obj
    | Error e -> Error (map_error e)

let instrumentation_pass (req : Lsp_protocol.instrumentation_pass_request) =
  let engine =
    Option.value (Engine_service.engine_of_string req.engine)
      ~default:Engine_service.Default
  in
  match
    Engine_service.instrumentation_pass ~engine ~generate_png:req.generate_png
      ~input_file:req.input_file
  with
  | Ok out -> Ok (Lsp_app.map_automata out)
  | Error e -> Error (map_error e)

let why_pass (req : Lsp_protocol.why_pass_request) =
  let engine =
    Option.value (Engine_service.engine_of_string req.engine)
      ~default:Engine_service.Default
  in
  match
    Engine_service.why_pass ~engine ~prefix_fields:req.prefix_fields
      ~disable_why3_optimizations:req.disable_why3_optimizations
      ~input_file:req.input_file
  with
  | Ok out -> Ok (Lsp_app.map_why out)
  | Error e -> Error (map_error e)

let obligations_pass (req : Lsp_protocol.obligations_pass_request) =
  let engine =
    Option.value (Engine_service.engine_of_string req.engine)
      ~default:Engine_service.Default
  in
  match
    Engine_service.obligations_pass ~engine ~prefix_fields:req.prefix_fields
      ~disable_why3_optimizations:req.disable_why3_optimizations
      ~prover:req.prover ~input_file:req.input_file
  with
  | Ok out -> Ok (Lsp_app.map_oblig out)
  | Error e -> Error (map_error e)

let eval_pass (req : Lsp_protocol.eval_pass_request) =
  let engine =
    Option.value (Engine_service.engine_of_string req.engine)
      ~default:Engine_service.Default
  in
  match
    Engine_service.eval_pass ~engine ~input_file:req.input_file
      ~trace_text:req.trace_text ~with_state:req.with_state
      ~with_locals:req.with_locals
  with
  | Ok out -> Ok out
  | Error e -> Error (map_error e)

let kobj_summary (req : Lsp_protocol.kobj_summary_request) =
  let engine =
    Option.value (Engine_service.engine_of_string req.engine)
      ~default:Engine_service.Default
  in
  match read_or_compile_kobj ~engine ~input_file:req.input_file with
  | Ok obj -> Ok (Kairos_object.render_summary obj)
  | Error msg -> Error msg

let kobj_clauses (req : Lsp_protocol.kobj_summary_request) =
  let engine =
    Option.value (Engine_service.engine_of_string req.engine)
      ~default:Engine_service.Default
  in
  match read_or_compile_kobj ~engine ~input_file:req.input_file with
  | Ok obj -> Ok (Kairos_object.render_clauses obj)
  | Error msg -> Error msg

let kobj_product (req : Lsp_protocol.kobj_summary_request) =
  let engine =
    Option.value (Engine_service.engine_of_string req.engine)
      ~default:Engine_service.Default
  in
  match read_or_compile_kobj ~engine ~input_file:req.input_file with
  | Ok obj -> Ok (Kairos_object.render_product obj)
  | Error msg -> Error msg

let kobj_contracts (req : Lsp_protocol.kobj_summary_request) =
  let engine =
    Option.value (Engine_service.engine_of_string req.engine)
      ~default:Engine_service.Default
  in
  match read_or_compile_kobj ~engine ~input_file:req.input_file with
  | Ok obj -> Ok (Kairos_object.render_product_contracts obj)
  | Error msg -> Error msg

let normalized_program (req : Lsp_protocol.kobj_summary_request) =
  let engine =
    Option.value (Engine_service.engine_of_string req.engine)
      ~default:Engine_service.Default
  in
  match Engine_service.normalized_program ~engine ~input_file:req.input_file with
  | Ok text -> Ok text
  | Error e -> Error (map_error e)

let ir_pretty_dump (req : Lsp_protocol.kobj_summary_request) =
  let engine =
    Option.value (Engine_service.engine_of_string req.engine)
      ~default:Engine_service.Default
  in
  match Engine_service.ir_pretty_dump ~engine ~input_file:req.input_file with
  | Ok text -> Ok text
  | Error e -> Error (map_error e)

let dot_png_from_text (req : Lsp_protocol.dot_png_from_text_request) =
  Graphviz_render.dot_png_from_text req.dot_text

let run ~engine (cfg : Lsp_protocol.config) =
  match Engine_service.run ~engine (pipeline_config_of_protocol cfg) with
  | Ok out -> Ok (Lsp_app.map_outputs out)
  | Error e -> Error (map_error e)

let run_with_callbacks ~engine ~should_cancel (cfg : Lsp_protocol.config)
    ~on_outputs_ready ~on_goals_ready ~on_goal_done =
  match
    Engine_service.run_with_callbacks ~engine ~should_cancel
      (pipeline_config_of_protocol cfg)
      ~on_outputs_ready:(fun out -> on_outputs_ready (Lsp_app.map_outputs out))
      ~on_goals_ready ~on_goal_done
  with
  | Ok out -> Ok (Lsp_app.map_outputs out)
  | Error e -> Error (map_error e)
