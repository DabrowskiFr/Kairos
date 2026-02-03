let write_text path content =
  let oc = open_out path in
  output_string oc content;
  close_out oc

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
  let residual_file =
    if Filename.check_suffix out_file ".dot"
    then out_file
    else out_file ^ ".dot"
  in
  let dot, labels = Dot_emit.dot_monitor_program ~show_labels program in
  write_text residual_file dot;
  if not show_labels then (
    let label_file =
      if Filename.check_suffix residual_file ".dot" then
        Filename.remove_extension residual_file ^ ".labels"
      else
        residual_file ^ ".labels"
    in
    write_text label_file labels
  )

let emit_obc_file ~(out_file:string) (program:Ast.program) : unit =
  let ensure_ext path =
    if Filename.check_suffix path ".obc+" then path
    else if Filename.check_suffix path ".obc" then path ^ "+"
    else path ^ ".obc+"
  in
  let path = ensure_ext out_file in
  let out = Obc_emit.compile_program program in
  write_text path out

let emit_why
  ~(prefix_fields:bool)
  ~(output_file:string option)
  ~(prove:bool)
  ~(prover:string)
  (program:Ast.program)
  : unit =
  let output_and_maybe_prove out =
    let output_path =
      match output_file with
      | Some path ->
          write_text path out;
          Some path
      | None -> None
    in
    if prove then (
      let prove_path, remove_after =
        match output_path with
        | Some path -> (path, false)
        | None ->
            let tmp = Filename.temp_file "obc2why3_" ".why" in
            write_text tmp out;
            (tmp, true)
      in
      Why_prove.prove_file ~prover ~file:prove_path ();
      if remove_after then Sys.remove prove_path
    );
    if output_path = None then print_string out
  in
  let why_ast = Why_stage.build_ast ~prefix_fields program in
  let out = Why_stage.emit_ast why_ast in
  output_and_maybe_prove out
