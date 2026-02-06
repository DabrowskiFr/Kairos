let write_text path content =
  let p = Fpath.v path in
  match Bos.OS.File.write p content with
  | Ok () -> ()
  | Error (`Msg msg) -> failwith msg

let file_size path =
  match Bos.OS.Path.stat (Fpath.v path) with
  | Ok st -> st.Unix.st_size
  | Error _ -> 0

let dump_ast_stage ~(stage:Stage_names.stage_id) ~(out:string option)
  (program:Ast.program) : (unit, string) result =
  let _ = Stage_names.to_string stage in
  let out =
    match out with
    | Some "-" -> None
    | other -> other
  in
  Ast_dump.dump_program_json ~out (Ast_user.of_ast program);
  Ok ()

let dump_ast_all
  ~(dir:string)
  ~(parsed:Ast_user.program)
  ~(automaton:Ast_automaton.program)
  ~(contracts:Ast_contracts.program)
  ~(monitor:Ast_monitor.program)
  ~(obc:Ast_obc.program)
  : (unit, string) result =
  if dir = "-" then Error "--dump-ast-all expects a directory, not '-'"
  else
    let d = Fpath.v dir in
    let ensure_dir () =
      match Bos.OS.Dir.exists d with
      | Ok true -> Ok ()
      | Ok false ->
          Bos.OS.Dir.create d
          |> Result.map (fun _ -> ())
          |> Result.map_error (fun (`Msg msg) -> msg)
      | Error (`Msg msg) -> Error msg
    in
    match ensure_dir () with
    | Error _ as err -> err
    | Ok () ->
        let write_stage name program =
          let path = Fpath.(d / (Stage_names.to_string name ^ ".json")) in
          Ast_dump.dump_program_json ~out:(Some (Fpath.to_string path)) program
        in
        write_stage Stage_names.Parsed parsed;
        write_stage Stage_names.Automaton (Ast_user.of_ast (Ast_automaton.to_ast automaton));
        write_stage Stage_names.Contracts (Ast_user.of_ast (Ast_contracts.to_ast contracts));
        write_stage Stage_names.Monitor (Ast_user.of_ast (Ast_monitor.to_ast monitor));
        write_stage Stage_names.Obc (Ast_user.of_ast (Ast_obc.to_ast obc));
        Ok ()


let emit_dot_files ~(show_labels:bool) ~(out_file:string) (program:Ast_automaton.program) : unit =
  let dot, labels = Dot_emit.dot_monitor_program ~show_labels program in
  if out_file = "-" then (
    print_string dot;
    if not show_labels then
      Log.warning "DOT labels suppressed when output is stdout"
  ) else (
    let residual_file =
      let p = Fpath.v out_file in
      if Fpath.has_ext ".dot" p then p else Fpath.add_ext ".dot" p
    in
    let residual_path = Fpath.to_string residual_file in
    write_text residual_path dot;
    Log.output_written "dot" residual_path (file_size residual_path);
    if not show_labels then (
      let label_file =
        if Fpath.has_ext ".dot" residual_file then
          Fpath.set_ext ".labels" residual_file
        else
          Fpath.add_ext ".labels" residual_file
      in
      let label_path = Fpath.to_string label_file in
      write_text label_path labels;
      Log.output_written "dot_labels" label_path (file_size label_path)
    )
  )

let emit_obc_file ~(out_file:string) (program:Ast_obc.program) : unit =
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
    Log.output_written "obc" path (file_size path)
  )

let emit_why3_vc ~(out_file:string) ~(why_text:string) : unit =
  let tasks = Why_prove.dump_why3_tasks ~text:why_text in
  let buf = Buffer.create 4096 in
  List.iteri
    (fun i task ->
       if i > 0 then Buffer.add_string buf "\n(* ---- goal ---- *)\n";
       Buffer.add_string buf task)
    tasks;
  let out = Buffer.contents buf in
  if out_file = "-" then
    print_string out
  else (
    write_text out_file out;
    Log.output_written "why3_vc" out_file (file_size out_file)
  )

let emit_smt2 ~(out_file:string) ~(prover:string) ~(why_text:string) : unit =
  let tasks = Why_prove.dump_smt2_tasks ~prover ~text:why_text in
  let buf = Buffer.create 4096 in
  List.iteri
    (fun i task ->
       if i > 0 then Buffer.add_string buf "\n; ---- goal ----\n";
       Buffer.add_string buf task)
    tasks;
  let out = Buffer.contents buf in
  if out_file = "-" then
    print_string out
  else (
    write_text out_file out;
    Log.output_written "smt2" out_file (file_size out_file)
  )

let emit_why
  ~(prefix_fields:bool)
  ~(output_file:string option)
  (program:Ast_obc.program)
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
  | Some path -> Log.output_written "why" path (file_size path)
  | None -> ()
  end;
  out

let prove_why
  ~(prover:string)
  ~(why_text:string)
  : unit =
  let t_prove = Unix.gettimeofday () in
  Log.stage_start Stage_names.Prove;
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
  Log.stage_end Stage_names.Prove duration_ms data;
  if summary.total = 0 then
    Log.warning
      ~stage:Stage_names.Prove
      "Why3: no proof goals found"
  else if failed = 0 then
    Log.stage_info
      (Some Stage_names.Prove)
      (Printf.sprintf "Why3: all goals proved (%d)" summary.total)
      []
  else
    Log.warning
      ~stage:Stage_names.Prove
      (Printf.sprintf
         "Why3: proof failed (%d/%d goals not proved)"
         failed summary.total);
  if result.status <> 0 then exit result.status
