type config = {
  dump_dot : string option;
  dump_dot_short : string option;
  dump_obc : string option;
  dump_obc_abstract : bool;
  dump_automata : string option;
  dump_product : string option;
  dump_obligations_map : string option;
  dump_prune_reasons : string option;
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
  smoke_tests : bool;
  debug_contract_ids : bool;
  prefix_fields : bool;
  input_file : string;
}

let with_smoke_tests (p : Ast.program) : Ast.program =
  let has_false_ensure (t : Ast.transition) =
    List.exists (fun (f : Ast.fo_o) -> f.value = Ast.FFalse) t.ensures
  in
  let add_transition_smoke (t : Ast.transition) : Ast.transition =
    if has_false_ensure t then t
    else { t with ensures = t.ensures @ [ Ast_provenance.with_origin Ast.Internal Ast.FFalse ] }
  in
  List.map (fun (n : Ast.node) -> { n with trans = List.map add_transition_smoke n.trans }) p

let check_stage label checks =
  if checks = [] then Ok () else Error (Printf.sprintf "%s: %s" label (String.concat " | " checks))

let run (cfg : config) : (unit, string) result =
  Obc_emit.set_debug_contract_ids cfg.debug_contract_ids;
  let log_stage msg = Log.debug msg in
  let result =
  match Pipeline.build_ast_with_info ~log:true ~input_file:cfg.input_file () with
  | Error err -> Error (Pipeline.error_to_string err)
  | Ok (asts, infos) -> (
      let r_check =
        if not cfg.check_ast then Ok ()
        else
          let open Ast_invariants in
          let r0 = check_stage "parsed" (check_program_basic asts.parsed) in
          let r1 =
            match r0 with
            | Error _ as err -> err
            | Ok () -> check_stage "automaton" (check_program_basic asts.automata_generation)
          in
          let r2 =
            match r1 with
            | Error _ as err -> err
            | Ok () ->
                check_stage "contracts"
                  (check_program_basic asts.contracts @ check_program_contracts asts.contracts)
          in
          let r3 =
            match r2 with
            | Error _ as err -> err
            | Ok () ->
                check_stage "instrumentation"
                  (check_program_basic asts.instrumentation @ check_program_monitor asts.instrumentation)
          in
          match r3 with
          | Error _ as err -> err
          | Ok () -> check_stage "obc" (check_program_basic asts.obc @ check_program_obc asts.obc)
      in
      match r_check with
      | Error _ as err -> err
      | Ok () -> (
          let obc_clean = asts.obc in
          let obc_backend =
            let p = List.map Abstract_model.to_ast_node asts.obc_abstract in
            if cfg.smoke_tests then with_smoke_tests p else p
          in
          let obc = obc_backend in
          let r0 =
            match cfg.dump_ast_stage with
            | None -> Ok ()
            | Some stage ->
                let program =
                  match stage with
                  | Stage_names.Parsed -> asts.parsed
                  | Stage_names.Automaton -> asts.automata_generation
                  | Stage_names.Contracts -> asts.contracts
                  | Stage_names.Instrumentation -> asts.instrumentation
                  | Stage_names.Obc -> obc_clean
                  | Stage_names.Why | Stage_names.Prove ->
                      invalid_arg "dump-ast does not support why/prove stages"
                in
                Io.dump_ast_stage ~stage ~out:cfg.dump_ast_out ~stable:cfg.dump_ast_stable program
          in
          let r1 =
            match r0 with
            | Error _ as err -> err
            | Ok () -> begin
                match cfg.dump_ast_all with
                | None -> Ok ()
                | Some dir ->
                    Io.dump_ast_all ~dir ~parsed:asts.parsed ~automaton:asts.automata_generation
                      ~contracts:asts.contracts ~instrumentation:asts.instrumentation ~obc:obc_clean
                      ~stable:cfg.dump_ast_stable
              end
          in
          match r1 with
          | Error _ as err -> err
          | Ok () -> begin
              match
                ( cfg.dump_dot,
                  cfg.dump_dot_short,
                  cfg.dump_obc,
                  cfg.dump_automata,
                  cfg.dump_product,
                  cfg.dump_obligations_map,
                  cfg.dump_prune_reasons )
              with
              | Some out_file, None, None, None, None, None, None ->
                  log_stage "emit dot";
                  Io.emit_dot_files ~show_labels:false ~out_file asts.automata_generation;
                  Ok ()
              | None, Some out_file, None, None, None, None, None ->
                  log_stage "emit dot (short)";
                  Io.emit_dot_files ~show_labels:false ~out_file asts.automata_generation;
                  Ok ()
              | None, None, Some out_file, None, None, None, None ->
                  log_stage "emit obc";
                  Io.emit_obc_file ~out_file ~use_abstract:cfg.dump_obc_abstract obc;
                  Ok ()
              | None, None, None, Some out_file, None, None, None ->
                  let mi = Option.value ~default:Stage_info.empty_instrumentation_info infos.instrumentation in
                  let text =
                    String.concat "\n"
                      (mi.guarantee_automaton_lines @ [ "" ] @ mi.assume_automaton_lines)
                  in
                  Io.write_text out_file text;
                  Ok ()
              | None, None, None, None, Some out_file, None, None ->
                  let mi = Option.value ~default:Stage_info.empty_instrumentation_info infos.instrumentation in
                  Io.write_text out_file (String.concat "\n" mi.product_lines);
                  Ok ()
              | None, None, None, None, None, Some out_file, None ->
                  let mi = Option.value ~default:Stage_info.empty_instrumentation_info infos.instrumentation in
                  Io.write_text out_file (String.concat "\n" mi.obligations_lines);
                  Ok ()
              | None, None, None, None, None, None, Some out_file ->
                  let mi = Option.value ~default:Stage_info.empty_instrumentation_info infos.instrumentation in
                  Io.write_text out_file (String.concat "\n" mi.prune_lines);
                  Ok ()
              | None, None, None, None, None, None, None ->
                  log_stage "emit why3";
                  begin match cfg.output_file with
                  | None when not cfg.prove ->
                      Error "Why3 output requires --dump-why <file.why|-> (or use --prove)"
                  | _ ->
                      Log.stage_start Stage_names.Why;
                      let t5 = Unix.gettimeofday () in
                      let why_text =
                        Io.emit_why ~prefix_fields:cfg.prefix_fields ~output_file:cfg.output_file
                          obc
                      in
                      Log.stage_end Stage_names.Why
                        (int_of_float ((Unix.gettimeofday () -. t5) *. 1000.))
                        [];
                      begin match cfg.dump_why3_vc with
                      | None -> ()
                      | Some out_file -> Io.emit_why3_vc ~out_file ~why_text
                      end;
                      begin match cfg.dump_smt2 with
                      | None -> ()
                      | Some out_file -> Io.emit_smt2 ~out_file ~prover:cfg.prover ~why_text
                      end;
                      if cfg.prove && not cfg.wp_only then
                        Io.prove_why ~prover:cfg.prover ~prover_cmd:cfg.prover_cmd ~why_text;
                      Ok ()
                  end
              | _ -> Ok ()
            end))
  in
  result
