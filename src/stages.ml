type config = {
  dump_dot : string option;
  dump_dot_short : string option;
  dump_obc : string option;
  dump_why3_vc : string option;
  dump_smt2 : string option;
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
  match Pipeline.build_ast ~log:true ~input_file:cfg.input_file () with
  | Error err -> Error (Pipeline.error_to_string err)
  | Ok asts ->
      let r0 =
        match cfg.dump_ast_stage with
        | None -> Ok ()
        | Some stage ->
            let program =
              match stage with
              | Stage_names.Parsed -> asts.parsed
              | Stage_names.Automaton -> asts.automaton
              | Stage_names.Contracts -> asts.contracts
              | Stage_names.Monitor -> asts.monitor
              | Stage_names.Obc -> asts.obc
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
                    ~parsed:asts.parsed
                    ~automaton:asts.automaton
                    ~contracts:asts.contracts
                    ~monitor:asts.monitor
                    ~obc:asts.obc
            end
      in
      match r1 with
      | Error _ as err -> err
      | Ok () ->
          begin match cfg.dump_dot, cfg.dump_dot_short, cfg.dump_obc with
      | Some out_file, None, None ->
          log_stage "emit dot";
          Stage_io.emit_dot_files ~show_labels:false ~out_file asts.automaton;
          Ok ()
      | None, Some out_file, None ->
          log_stage "emit dot (short)";
          Stage_io.emit_dot_files ~show_labels:false ~out_file asts.automaton;
          Ok ()
      | None, None, Some out_file ->
          log_stage "emit obc";
          Stage_io.emit_obc_file ~out_file asts.obc;
          Ok ()
      | None, None, None ->
          log_stage "emit why3";
          begin
            match cfg.output_file with
            | None when not cfg.prove ->
                Error "Why3 output requires --dump-why <file.why|-> (or use --prove)"
            | _ ->
                Logger.stage_start Stage_names.Why;
                let t5 = Unix.gettimeofday () in
                let why_text =
                  Stage_io.emit_why
                    ~prefix_fields:cfg.prefix_fields
                    ~output_file:cfg.output_file
                    asts.obc
                in
                Logger.stage_end Stage_names.Why
                  (int_of_float ((Unix.gettimeofday () -. t5) *. 1000.))
                  [];
                begin match cfg.dump_why3_vc with
                | None -> ()
                | Some out_file ->
                    Stage_io.emit_why3_vc ~out_file ~why_text
                end;
                begin match cfg.dump_smt2 with
                | None -> ()
                | Some out_file ->
                    Stage_io.emit_smt2 ~out_file ~prover:cfg.prover ~why_text
                end;
                if cfg.prove then
                  Stage_io.prove_why
                    ~prover:cfg.prover
                    ~why_text;
                Ok ()
          end
      | _ -> Ok ()
          end
