type config = {
  dump_dot : string option;
  dump_dot_labels : string option;
  dump_obc : string option;
  dump_ast_stage : Stage_names.stage_id option;
  dump_ast_out : string option;
  dump_ast_all : string option;
  trace : bool;
  output_file : string option;
  prove : bool;
  prover : string;
  prefix_fields : bool;
  input_file : string;
}

let run (cfg:config) : (unit, string) result =
  let log_stage msg =
    if cfg.trace then prerr_endline ("[stage] " ^ msg)
  in
  log_stage "parse";
  let p_parsed = Frontend.parse_file cfg.input_file in
  log_stage "automaton";
  let p_automaton = Middle_end.stage_automaton p_parsed in
  log_stage "contracts";
  let p_contracts = Middle_end.stage_contracts p_automaton in
  log_stage "monitor injection";
  let p_mid = Middle_end.stage_monitor_injection p_contracts in
  log_stage "obc stage";
  let p_obc = Obc_stage.run p_mid in
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
        in
        Stage_io.dump_ast_stage ~stage ~out:cfg.dump_ast_out program
  in
  let r1 =
    match r0 with
    | Error _ as err -> err
    | Ok () ->
        begin match cfg.dump_ast_all with
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
      begin match cfg.dump_dot, cfg.dump_dot_labels, cfg.dump_obc with
      | Some out_file, None, None
      | None, Some out_file, None ->
          let show_labels = cfg.dump_dot_labels <> None in
          log_stage "emit dot";
          Stage_io.emit_dot_files ~show_labels ~out_file p_automaton;
          Ok ()
      | None, None, Some out_file ->
          log_stage "emit obc";
          Stage_io.emit_obc_file ~out_file p_obc;
          Ok ()
      | None, None, None ->
          log_stage "emit why3";
          Stage_io.emit_why
            ~prefix_fields:cfg.prefix_fields
            ~output_file:cfg.output_file
            ~prove:cfg.prove
            ~prover:cfg.prover
            p_obc;
          Ok ()
      | _ -> Ok ()
      end
