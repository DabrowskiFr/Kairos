type config = {
  dump_dot : string option;
  dump_dot_short : string option;
  dump_obc : string option;
  dump_ast_stage : Stage_names.stage_id option;
  dump_ast_out : string option;
  dump_ast_all : string option;
  output_file : string option;
  prove : bool;
  prover : string;
  prefix_fields : bool;
  input_file : string;
}

let run (cfg:config) : (unit, string) result =
  let log_stage msg =
    Logger.emit {
      Logger.kind = Logger.StageInfo;
      stage = None;
      level = Logger.Trace;
      relevance = Logger.Low;
      message = msg;
      data = [];
      duration_ms = None;
    }
  in
  let program_stats (p:Ast.program) : (string * string) list =
    let nodes = List.length p in
    let transitions =
      List.fold_left (fun acc n -> acc + List.length n.Ast.trans) 0 p
    in
    let requires =
      List.fold_left
        (fun acc n ->
           acc + List.fold_left (fun a t -> a + List.length t.Ast.requires) 0 n.Ast.trans)
        0 p
    in
    let ensures =
      List.fold_left
        (fun acc n ->
           acc + List.fold_left (fun a t -> a + List.length t.Ast.ensures) 0 n.Ast.trans)
        0 p
    in
    let guards =
      List.fold_left
        (fun acc n ->
           acc +
           List.fold_left
             (fun a t -> if t.Ast.guard = None then a else a + 1)
             0 n.Ast.trans)
        0 p
    in
    let locals =
      List.fold_left (fun acc n -> acc + List.length n.Ast.locals) 0 p
    in
    [("nodes", string_of_int nodes);
     ("transitions", string_of_int transitions);
     ("requires", string_of_int requires);
     ("ensures", string_of_int ensures);
     ("guards", string_of_int guards);
     ("locals", string_of_int locals)]
  in
  let emit_automaton_debug_stats (p:Ast.program) =
    let nodes = List.length p in
    let edges =
      List.fold_left (fun acc n -> acc + List.length n.Ast.trans) 0 p
    in
    Logger.emit {
      Logger.kind = Logger.StageInfo;
      stage = Some Stage_names.Automaton;
      level = Logger.Debug;
      relevance = Logger.Medium;
      message = "automaton stats";
      data = [
        "nodes", string_of_int nodes;
        "edges", string_of_int edges;
      ];
      duration_ms = None;
    }
  in
  let t0 = Unix.gettimeofday () in
  Logger.stage_start Stage_names.Parsed;
  let p_parsed = Frontend.parse_file cfg.input_file in
  Logger.stage_end Stage_names.Parsed
    (int_of_float ((Unix.gettimeofday () -. t0) *. 1000.))
    (program_stats p_parsed);
  log_stage "automaton";
  let t1 = Unix.gettimeofday () in
  Logger.stage_start Stage_names.Automaton;
  let p_automaton = Middle_end.stage_automaton p_parsed in
  emit_automaton_debug_stats p_automaton;
  Logger.stage_end Stage_names.Automaton
    (int_of_float ((Unix.gettimeofday () -. t1) *. 1000.))
    (program_stats p_automaton);
  log_stage "contracts";
  let t2 = Unix.gettimeofday () in
  Logger.stage_start Stage_names.Contracts;
  let p_contracts = Middle_end.stage_contracts p_automaton in
  Logger.stage_end Stage_names.Contracts
    (int_of_float ((Unix.gettimeofday () -. t2) *. 1000.))
    (program_stats p_contracts);
  log_stage "monitor injection";
  let t3 = Unix.gettimeofday () in
  Logger.stage_start Stage_names.Monitor;
  let p_mid = Middle_end.stage_monitor_injection p_contracts in
  Logger.stage_end Stage_names.Monitor
    (int_of_float ((Unix.gettimeofday () -. t3) *. 1000.))
    (program_stats p_mid);
  log_stage "obc stage";
  let t4 = Unix.gettimeofday () in
  Logger.stage_start Stage_names.Obc;
  let p_obc = Obc_stage.run p_mid in
  Logger.stage_end Stage_names.Obc
    (int_of_float ((Unix.gettimeofday () -. t4) *. 1000.))
    (program_stats p_obc);
  let r0 =
    match cfg.dump_ast_stage with
    | None -> Ok ()
    | Some stage ->
        let program =
          match stage with
          | Stage_names.Parsed -> p_parsed
          | Stage_names.Automaton -> p_automaton
          | Stage_names.Contracts -> p_contracts
          | Stage_names.Monitor -> p_mid
          | Stage_names.Obc -> p_obc
          | Stage_names.Why
          | Stage_names.Prove ->
              invalid_arg "dump-ast does not support why/prove stages"
        in
        Stage_io.dump_ast_stage ~stage ~out:cfg.dump_ast_out program
  in
  let r1 =
    match r0 with
    | Error _ as err -> err
    | Ok () ->
        begin
          match cfg.dump_ast_all with
          | None -> Ok ()
          | Some dir ->
              Stage_io.dump_ast_all
                ~dir
                ~parsed:p_parsed
                ~automaton:p_automaton
                ~contracts:p_contracts
                ~monitor:p_mid
                ~obc:p_obc
        end
  in
  match r1 with
  | Error _ as err -> err
  | Ok () ->
      begin match cfg.dump_dot, cfg.dump_dot_short, cfg.dump_obc with
      | Some out_file, None, None ->
          log_stage "emit dot";
          Stage_io.emit_dot_files ~show_labels:true ~out_file p_automaton;
          Ok ()
      | None, Some out_file, None ->
          log_stage "emit dot (short)";
          Stage_io.emit_dot_files ~show_labels:false ~out_file p_automaton;
          Ok ()
      | None, None, Some out_file ->
          log_stage "emit obc";
          Stage_io.emit_obc_file ~out_file p_obc;
          Ok ()
      | None, None, None ->
          log_stage "emit why3";
          begin
            match cfg.output_file with
            | None when not cfg.prove ->
                Error "Why3 output requires --dump-why <file.why|-> (or use --prove)"
            | _ ->
                let t5 = Unix.gettimeofday () in
                Logger.stage_start Stage_names.Why;
                let why_text =
                  Stage_io.emit_why
                  ~prefix_fields:cfg.prefix_fields
                  ~output_file:cfg.output_file
                  p_obc
                in
                Logger.stage_end Stage_names.Why
                  (int_of_float ((Unix.gettimeofday () -. t5) *. 1000.))
                  [];
                if cfg.prove then
                  Stage_io.prove_why
                    ~prover:cfg.prover
                    ~output_file:cfg.output_file
                    ~why_text;
                Ok ()
          end
      | _ -> Ok ()
      end
