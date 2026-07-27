module Contract = Engine_contract
module Flow = Engine_flow

type config = Contract.config
type error = Contract.error

type source_diagnostic = {
  line : int;
  column : int;
  severity : int;
  source : string;
  message : string;
}

type semantic_symbols = {
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

type generated_file = {
  file_name : string;
  contents : string;
}

let default_proof_jobs = Runtime_defaults.default_proof_jobs
let error_to_string = Contract.error_to_string

let make_config ~input_file ~wp_only ~smoke_tests ~timeout_s
    ~compute_proof_diagnostics ~prove ?proof_jobs
    ?(dump_failed_smt = false) ?(collect_ir_metrics = false)
    ?proof_progress_path ?(stop_on_first_nonvalid = false)
    ?(proof_encoding = Contract.default_proof_encoding)
    ?(proof_optimizations = Contract.default_proof_optimizations)
    ~generate_vc_text ~generate_smt_text ~generate_dot_png () =
  {
    Contract.input_file;
    wp_only;
    smoke_tests;
    timeout_s;
    compute_proof_diagnostics;
    prove;
    proof_jobs = Option.value proof_jobs ~default:(default_proof_jobs ());
    generate_why_text = not prove;
    generate_vc_text;
    generate_smt_text;
    generate_dot_png;
    dump_failed_smt;
    collect_ir_metrics;
    proof_progress_path;
    stop_on_first_nonvalid;
    proof_encoding;
    proof_optimizations;
  }

let instrumentation_pass ~generate_png ~input_file =
  Flow.instrumentation_pass ~generate_png ~input_file

let why_pass ~input_file =
  Flow.why_pass ~proof_encoding:Pipeline_config.default_proof_encoding
    ~proof_optimizations:Pipeline_config.default_proof_optimizations ~input_file

let why_pass_with_options ~proof_encoding ~proof_optimizations ~input_file =
  Flow.why_pass ~proof_encoding ~proof_optimizations ~input_file

let obligations_pass ~input_file =
  Flow.obligations_pass
    ~proof_encoding:Pipeline_config.default_proof_encoding
    ~proof_optimizations:Pipeline_config.default_proof_optimizations ~input_file

let obligations_pass_with_options ~proof_encoding ~proof_optimizations
    ~input_file =
  Flow.obligations_pass ~proof_encoding ~proof_optimizations ~input_file

let cost_report ~proof_encoding ~proof_optimizations ~input_file =
  Flow.cost_report ~proof_encoding ~proof_optimizations ~input_file

let normalized_program ~input_file =
  Flow.normalized_program
    ~proof_encoding:Pipeline_config.default_proof_encoding
    ~proof_optimizations:Pipeline_config.default_proof_optimizations ~input_file

let ir_pretty_dump ~input_file =
  Flow.ir_pretty_dump
    ~proof_encoding:Pipeline_config.default_proof_encoding
    ~proof_optimizations:Pipeline_config.default_proof_optimizations ~input_file

let normalized_program_with_options ~proof_encoding ~proof_optimizations
    ~input_file =
  Flow.normalized_program ~proof_encoding ~proof_optimizations ~input_file

let ir_pretty_dump_with_options ~proof_encoding ~proof_optimizations
    ~input_file =
  Flow.ir_pretty_dump ~proof_encoding ~proof_optimizations ~input_file

let run = Flow.run

let run_with_callbacks ~should_cancel config ~on_outputs_ready
    ~on_goals_ready ~on_goal_done =
  Flow.run_with_callbacks ~should_cancel config ~on_outputs_ready
    ~on_goals_ready ~on_goal_done

let parse_line_column message =
  let pattern = Str.regexp ".*:\\([0-9]+\\):\\([0-9]+\\)" in
  if Str.string_match pattern message 0 then
    Some
      ( int_of_string (Str.matched_group 1 message),
        int_of_string (Str.matched_group 2 message) )
  else None

let source_diagnostic ~severity ~source ~message =
  let line, column =
    match parse_line_column message with
    | Some (line, column) -> (max 0 (line - 1), max 0 (column - 1))
    | None -> (0, 0)
  in
  { line; column; severity; source; message }

let frontend_error_source = function
  | Kx_frontend_error.Parse -> "kairos-parse"
  | Kx_frontend_error.Elaboration -> "kairos-elaboration"
  | Kx_frontend_error.Type -> "kairos-type"
  | Kx_frontend_error.Well_formedness -> "kairos-well-formedness"
  | Kx_frontend_error.Internal -> "kairos-internal"

let source_diagnostics ~text =
  try
    let _source, info =
      Kx_parse_api.parse_source_text_with_info ~filename:"<client-buffer>"
        ~text
    in
    let diagnostics = ref [] in
    List.iter
      (fun error ->
        diagnostics :=
          source_diagnostic ~severity:1 ~source:"kairos-parse"
            ~message:error.Kx_parse_api.message
          :: !diagnostics)
      info.Kx_parse_api.parse_errors;
    List.iter
      (fun warning ->
        diagnostics :=
          source_diagnostic ~severity:2 ~source:"kairos-parse"
            ~message:warning
          :: !diagnostics)
      info.Kx_parse_api.warnings;
    List.rev !diagnostics
  with
  | Kx_frontend_error.Error error ->
      [
        source_diagnostic ~severity:1
          ~source:(frontend_error_source error.kind)
          ~message:error.message;
      ]
  | exn ->
      [
        source_diagnostic ~severity:1 ~source:"kairos-internal"
          ~message:(Printexc.to_string exn);
      ]

let semantic_symbols ~text =
  try
    let source, _info =
      Kx_parse_api.parse_source_text_with_info ~filename:"<client-buffer>"
        ~text
    in
    let all = Hashtbl.create 256 in
    let nodes = Hashtbl.create 64 in
    let states = Hashtbl.create 128 in
    let variables = Hashtbl.create 256 in
    let add table value =
      if value <> "" then Hashtbl.replace table value ()
    in
    List.iter
      (fun (node : Kx_ast.node) ->
        let semantics = node.semantics in
        add nodes semantics.sem_nname;
        add all semantics.sem_nname;
        List.iter
          (fun state ->
            add states state;
            add all state)
          semantics.sem_states;
        List.iter
          (fun variable ->
            add variables variable.Kx_core_syntax.vname;
            add all variable.Kx_core_syntax.vname)
          (semantics.sem_inputs @ semantics.sem_outputs
         @ semantics.sem_locals))
      source.nodes;
    let keys table =
      Hashtbl.to_seq_keys table |> List.of_seq
      |> List.sort_uniq String.compare
    in
    Some
      {
        all = keys all;
        nodes = keys nodes;
        states = keys states;
        variables = keys variables;
      }
  with _ -> None

let structured_frontend_error (error : Kx_frontend_error.t) =
  match error.kind with
  | Kx_frontend_error.Parse -> Contract.Parse_error error.message
  | Kx_frontend_error.Elaboration ->
      Contract.Elaboration_error error.message
  | Kx_frontend_error.Type -> Contract.Type_error error.message
  | Kx_frontend_error.Well_formedness ->
      Contract.Well_formedness_error error.message
  | Kx_frontend_error.Internal -> Contract.Internal_error error.message

let read_text input_file =
  try
    let channel = open_in_bin input_file in
    let length = in_channel_length channel in
    let text = really_input_string channel length in
    close_in channel;
    Ok text
  with exn -> Error (Contract.Io_error (Printexc.to_string exn))

let surface_dump ~input_file =
  match read_text input_file with
  | Error _ as error -> error
  | Ok text -> (
      try
        let surface, _ =
          Kx_parse_api.parse_surface_text_with_info ~filename:input_file
            ~text
        in
        Ok (Kx_parse_api.surface_source_to_json surface)
      with
      | Kx_frontend_error.Error error ->
          Error (structured_frontend_error error)
      | exn -> Error (Contract.Internal_error (Printexc.to_string exn)))

let elaborated_dump ~input_file =
  match read_text input_file with
  | Error _ as error -> error
  | Ok text -> (
      try
        let source, _ =
          Kx_parse_api.parse_source_text_with_info ~filename:input_file ~text
        in
        Ok (Kx_parse_api.source_to_json source)
      with
      | Kx_frontend_error.Error error ->
          Error (structured_frontend_error error)
      | exn -> Error (Contract.Internal_error (Printexc.to_string exn)))

let frontend_summary ~input_file =
  match Kairos_frontend.parse_input ~input_file with
  | Error error -> Error (Flow.error_of_frontend error)
  | Ok frontend ->
      let nodes = frontend.Kairos_frontend.verification_model in
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

let generate_c ~input_file =
  match Kairos_frontend.parse_input ~input_file with
  | Error error -> Error (Flow.error_of_frontend error)
  | Ok frontend -> (
      match
        Kairos_c_codegen.C_codegen.emit_program
          frontend.Kairos_frontend.verification_model
      with
      | Error message -> Error (Contract.Flow_error message)
      | Ok files ->
          Ok
            (List.map
               (fun (file : Kairos_c_codegen.C_codegen.generated_file) ->
                 { file_name = file.file_name; contents = file.contents })
               files))
