type config = {
  dump_dot : string option;
  dump_dot_short : string option;
  dump_obc : string option;
  dump_why3_vc : string option;
  dump_smt2 : string option;
  dump_ast_stage : Stage_names.stage_id option;
  dump_ast_out : string option;
  dump_ast_all : string option;
  dump_ast_stable : bool;
  check_ast : bool;
  output_file : string option;
  prove : bool;
  prover : string;
  prover_cmd : string option;
  wp_only : bool;
  prefix_fields : bool;
  input_file : string;
}

let check_stage label checks =
  if checks = [] then Ok ()
  else Error (Printf.sprintf "%s: %s" label (String.concat " | " checks))

let run (cfg:config) : (unit, string) result =
  let log_stage msg =
    Log.debug msg
  in
  match Pipeline.build_ast ~log:true ~input_file:cfg.input_file () with
  | Error err -> Error (Pipeline.error_to_string err)
  | Ok asts ->
      let r_check =
        if not cfg.check_ast then Ok ()
        else
          let open Ast_invariants in
          let r0 =
            check_stage "parsed"
              (check_program_basic asts.parsed)
          in
          let r1 =
            match r0 with
            | Error _ as err -> err
            | Ok () ->
                check_stage "automaton"
                  (check_program_basic asts.monitor_generation)
          in
          let r2 =
            match r1 with
            | Error _ as err -> err
            | Ok () ->
                check_stage "contracts"
                  (check_program_basic asts.contracts
                   @ check_program_contracts asts.contracts)
          in
          let r3 =
            match r2 with
            | Error _ as err -> err
            | Ok () ->
                check_stage "monitor"
                  (check_program_basic asts.monitor
                   @ check_program_monitor asts.monitor)
          in
          match r3 with
          | Error _ as err -> err
          | Ok () ->
              check_stage "obc"
                (check_program_basic asts.obc
                 @ check_program_obc asts.obc)
      in
      match r_check with
      | Error _ as err -> err
      | Ok () ->
      let r0 =
        match cfg.dump_ast_stage with
        | None -> Ok ()
        | Some stage ->
            let program =
              match stage with
              | Stage_names.Parsed -> asts.parsed
              | Stage_names.Automaton -> asts.monitor_generation
              | Stage_names.Contracts -> asts.contracts
              | Stage_names.Monitor -> asts.monitor
              | Stage_names.Obc -> asts.obc
              | Stage_names.Why
              | Stage_names.Prove ->
                  invalid_arg "dump-ast does not support why/prove stages"
            in
            Io.dump_ast_stage
              ~stage
              ~out:cfg.dump_ast_out
              ~stable:cfg.dump_ast_stable
              program
      in
      let r1 =
        match r0 with
        | Error _ as err -> err
        | Ok () ->
            begin
              match cfg.dump_ast_all with
              | None -> Ok ()
              | Some dir ->
                  Io.dump_ast_all
                    ~dir
                    ~parsed:asts.parsed
                    ~automaton:asts.monitor_generation
                    ~contracts:asts.contracts
                    ~monitor:asts.monitor
                    ~obc:asts.obc
                    ~stable:cfg.dump_ast_stable
            end
      in
      match r1 with
      | Error _ as err -> err
      | Ok () ->
          begin match cfg.dump_dot, cfg.dump_dot_short, cfg.dump_obc with
      | Some out_file, None, None ->
          log_stage "emit dot";
          Io.emit_dot_files ~show_labels:false ~out_file asts.monitor_generation;
          Ok ()
      | None, Some out_file, None ->
          log_stage "emit dot (short)";
          Io.emit_dot_files ~show_labels:false ~out_file asts.monitor_generation;
          Ok ()
      | None, None, Some out_file ->
          log_stage "emit obc";
          Io.emit_obc_file ~out_file asts.obc;
          Ok ()
      | None, None, None ->
          log_stage "emit why3";
          begin
            match cfg.output_file with
            | None when not cfg.prove ->
                Error "Why3 output requires --dump-why <file.why|-> (or use --prove)"
            | _ ->
                Log.stage_start Stage_names.Why;
                let t5 = Unix.gettimeofday () in
                let why_text =
                  Io.emit_why
                    ~prefix_fields:cfg.prefix_fields
                    ~output_file:cfg.output_file
                    asts.obc
                in
                Log.stage_end Stage_names.Why
                  (int_of_float ((Unix.gettimeofday () -. t5) *. 1000.))
                  [];
                begin match cfg.dump_why3_vc with
                | None -> ()
                | Some out_file ->
                    Io.emit_why3_vc ~out_file ~why_text
                end;
                begin match cfg.dump_smt2 with
                | None -> ()
                | Some out_file ->
                    Io.emit_smt2 ~out_file ~prover:cfg.prover ~why_text
                end;
                if cfg.prove && not cfg.wp_only then
                  Io.prove_why
                    ~prover:cfg.prover
                    ~prover_cmd:cfg.prover_cmd
                    ~why_text;
                Ok ()
          end
      | _ -> Ok ()
          end
