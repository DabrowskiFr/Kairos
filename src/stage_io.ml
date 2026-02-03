let write_text path content =
  let oc = open_out path in
  output_string oc content;
  close_out oc

let file_size path =
  (Unix.stat path).Unix.st_size

let dump_ast_stage ~(stage:Stage_names.stage_id) ~(out:string option)
  (program:Ast.program) : (unit, string) result =
  let _ = Stage_names.to_string stage in
  let out =
    match out with
    | Some "-" -> None
    | other -> other
  in
  Ast_dump.dump_program_json ~out program;
  Ok ()

let dump_ast_all
  ~(dir:string)
  ~(parsed:Ast.program)
  ~(automaton:Ast.program)
  ~(contracts:Ast.program)
  ~(monitor:Ast.program)
  ~(obc:Ast.program)
  : (unit, string) result =
  if dir = "-" then Error "--dump-ast-all expects a directory, not '-'"
  else
    let ensure_dir d =
      if Sys.file_exists d then (
        if not (Sys.is_directory d) then
          Error ("--dump-ast-all: not a directory: " ^ d)
        else Ok ()
      ) else (
        Unix.mkdir d 0o755;
        Ok ()
      )
    in
    match ensure_dir dir with
    | Error _ as err -> err
    | Ok () ->
        let write_stage name program =
          let path = Filename.concat dir (Stage_names.to_string name ^ ".json") in
          Ast_dump.dump_program_json ~out:(Some path) program
        in
        write_stage Stage_names.Parsed parsed;
        write_stage Stage_names.Automaton automaton;
        write_stage Stage_names.Contracts contracts;
        write_stage Stage_names.Monitor monitor;
        write_stage Stage_names.Obc obc;
        Ok ()


let emit_dot_files ~(show_labels:bool) ~(out_file:string) (program:Ast.program) : unit =
  let dot, labels = Dot_emit.dot_monitor_program ~show_labels program in
  if out_file = "-" then (
    print_string dot;
    if not show_labels then
      Logger.warning "DOT labels suppressed when output is stdout"
  ) else (
    let residual_file =
      if Filename.check_suffix out_file ".dot"
      then out_file
      else out_file ^ ".dot"
    in
    write_text residual_file dot;
    Logger.output_written "dot" residual_file (file_size residual_file);
    if not show_labels then (
      let label_file =
        if Filename.check_suffix residual_file ".dot" then
          Filename.remove_extension residual_file ^ ".labels"
        else
          residual_file ^ ".labels"
      in
      write_text label_file labels;
      Logger.output_written "dot_labels" label_file (file_size label_file)
    )
  )

let emit_obc_file ~(out_file:string) (program:Ast.program) : unit =
  let out = Obc_emit.compile_program program in
  if out_file = "-" then
    print_string out
  else (
    let ensure_ext path =
      if Filename.check_suffix path ".obc+" then path
      else if Filename.check_suffix path ".obc" then path ^ "+"
      else path ^ ".obc+"
    in
    let path = ensure_ext out_file in
    write_text path out;
    Logger.output_written "obc" path (file_size path)
  )

let emit_why
  ~(prefix_fields:bool)
  ~(output_file:string option)
  (program:Ast.program)
  : string =
  let why_ast = Why_stage.build_ast ~prefix_fields program in
  let out = Why_stage.emit_ast why_ast in
  begin match output_file with
  | Some "-" -> print_string out
  | Some path -> write_text path out
  | None -> ()
  end;
  begin match output_file with
  | Some "-" -> ()
  | Some path -> Logger.output_written "why" path (file_size path)
  | None -> ()
  end;
  out

let prove_why
  ~(prover:string)
  ~(why_text:string)
  : unit =
  let t_prove = Unix.gettimeofday () in
  Logger.stage_start Stage_names.Prove;
  let result = Why_prove.prove_text ~prover ~text:why_text () in
  let duration_ms =
    int_of_float ((Unix.gettimeofday () -. t_prove) *. 1000.)
  in
  let summary = result.summary in
  let failed =
    summary.invalid + summary.unknown + summary.timeout + summary.failure
  in
  let data = [
    "total", string_of_int summary.total;
    "valid", string_of_int summary.valid;
    "invalid", string_of_int summary.invalid;
    "unknown", string_of_int summary.unknown;
    "timeout", string_of_int summary.timeout;
    "failure", string_of_int summary.failure;
  ] in
  Logger.stage_end Stage_names.Prove duration_ms data;
  if summary.total = 0 then
    Logger.warning
      ~stage:Stage_names.Prove
      "Why3: no proof goals found"
  else if failed = 0 then
    Logger.emit {
      kind = Logger.StageInfo;
      stage = Some Stage_names.Prove;
      level = Logger.Normal;
      relevance = Logger.High;
      message = Printf.sprintf "Why3: all goals proved (%d)" summary.total;
      data = [];
      duration_ms = None;
    }
  else
    Logger.warning
      ~stage:Stage_names.Prove
      (Printf.sprintf
         "Why3: proof failed (%d/%d goals not proved)"
         failed summary.total);
  if result.status <> 0 then exit result.status
