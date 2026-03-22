open Cmdliner

let dump_ast_conv =
  let parse s =
    match String.split_on_char ':' s with
    | [ stage; out ] when stage <> "" && out <> "" -> Ok (stage, out)
    | _ -> Error (`Msg "Expected STAGE:FILE for --dump-ast")
  in
  let print fmt (stage, out) = Format.fprintf fmt "%s:%s" stage out in
  Arg.conv (parse, print)

let log_level_conv =
  let parse = function
    | "quiet" -> Ok None
    | "error" -> Ok (Some Logs.Error)
    | "warning" -> Ok (Some Logs.Warning)
    | "info" -> Ok (Some Logs.Info)
    | "debug" -> Ok (Some Logs.Debug)
    | "app" -> Ok (Some Logs.App)
    | other -> Error (`Msg ("Unknown log level: " ^ other))
  in
  let print fmt = function
    | None -> Format.pp_print_string fmt "quiet"
    | Some Logs.Error -> Format.pp_print_string fmt "error"
    | Some Logs.Warning -> Format.pp_print_string fmt "warning"
    | Some Logs.Info -> Format.pp_print_string fmt "info"
    | Some Logs.Debug -> Format.pp_print_string fmt "debug"
    | Some Logs.App -> Format.pp_print_string fmt "app"
  in
  Arg.conv (parse, print)

let why_mode_conv =
  let parse s =
    match Pipeline.why_translation_mode_of_string s with
    | Some mode -> Ok mode
    | None -> Error (`Msg "Unknown why mode: expected no-automata or monitor")
  in
  let print fmt mode =
    Format.pp_print_string fmt (Pipeline.string_of_why_translation_mode mode)
  in
  Arg.conv (parse, print)

let run dump_dot dump_dot_short dump_automata dump_product
    dump_obligations_map dump_prune_reasons dump_why3_vc dump_smt2 emit_kobj dump_kobj_summary
    dump_kobj_clauses dump_kobj_product dump_kobj_product_contracts dump_json dump_json_stable
    dump_proof_traces_json dump_native_unsat_core_json dump_native_counterexample_json
    proof_traces_failed_only proof_traces_fast proof_trace_goal_index dump_ast
    dump_ast_all dump_ast_stable check_ast output_file prove prover prover_cmd timeout_s why_mode wp_only
    smoke_tests eval_trace eval_out eval_with_state eval_with_locals debug_contract_ids log_level
    log_file file =
  Log.setup ~level:log_level ~log_file;
  let read_all_stdin () =
    let b = Buffer.create 4096 in
    (try
       while true do
         Buffer.add_string b (input_line stdin);
         Buffer.add_char b '\n'
       done
     with End_of_file -> ());
    Buffer.contents b
  in
  let dump_ast_stage, dump_ast_out =
    match (dump_ast, dump_json, dump_json_stable) with
    | Some (stage, out), None, None -> (Some stage, Some out)
    | None, Some out, None -> (Some "contracts", Some out)
    | None, None, Some out -> (Some "contracts", Some out)
    | None, None, None -> (None, None)
    | _ -> (None, None)
  in
  let validate () =
    let dump_mode_count =
      List.fold_left (fun acc b -> if b then acc + 1 else acc) 0
        [
          dump_dot <> None;
          dump_dot_short <> None;
          dump_automata <> None;
          dump_product <> None;
          dump_obligations_map <> None;
          dump_prune_reasons <> None;
          emit_kobj <> None;
          dump_kobj_summary <> None;
          dump_kobj_clauses <> None;
          dump_kobj_product <> None;
          dump_kobj_product_contracts <> None;
          dump_proof_traces_json <> None;
          dump_native_unsat_core_json <> None;
          dump_native_counterexample_json <> None;
        ]
    in
    if dump_ast <> None && dump_json <> None then
      Error "--dump-json and --dump-ast are mutually exclusive"
    else if dump_json <> None && dump_json_stable <> None then
      Error "--dump-json and --dump-json-stable are mutually exclusive"
    else if dump_ast <> None && dump_ast_all <> None then
      Error "--dump-ast and --dump-ast-all are mutually exclusive"
    else if (dump_json <> None || dump_json_stable <> None) && dump_ast_all <> None then
      Error "--dump-json and --dump-ast-all are mutually exclusive"
    else if
     (dump_dot <> None || dump_dot_short <> None || dump_ast_stage <> None
     || dump_ast_all <> None || dump_automata <> None || dump_product <> None
        || dump_obligations_map <> None || dump_prune_reasons <> None || emit_kobj <> None
        || dump_kobj_summary <> None || dump_kobj_clauses <> None || dump_kobj_product <> None
        || dump_kobj_product_contracts <> None)
      && (prove || wp_only || output_file <> None)
    then Error "--dump-dot/--dump-ast cannot be combined with --prove or --dump-why"
    else if
      (dump_proof_traces_json <> None || dump_native_unsat_core_json <> None
      || dump_native_counterexample_json <> None)
      && (dump_dot <> None || dump_dot_short <> None || dump_ast_stage <> None
        || dump_ast_all <> None || dump_automata <> None || dump_product <> None
        || dump_obligations_map <> None || dump_prune_reasons <> None || emit_kobj <> None
        || dump_kobj_summary <> None || dump_kobj_clauses <> None || dump_kobj_product <> None
        || dump_kobj_product_contracts <> None
        || dump_why3_vc <> None
        || dump_smt2 <> None || output_file <> None)
    then
      Error
        "--dump-proof-traces-json/--dump-native-unsat-core-json/--dump-native-counterexample-json cannot be combined with other dump modes"
    else if
      (dump_why3_vc <> None || dump_smt2 <> None)
      && (dump_dot <> None || dump_dot_short <> None || dump_ast_stage <> None
        || dump_ast_all <> None || dump_automata <> None || dump_product <> None
        || dump_obligations_map <> None || dump_prune_reasons <> None || emit_kobj <> None
        || dump_kobj_summary <> None || dump_kobj_clauses <> None || dump_kobj_product <> None
        || dump_kobj_product_contracts <> None)
    then Error "--dump-why3-vc/--dump-smt2 cannot be combined with --dump-dot/--dump-ast"
    else if dump_mode_count > 1 then
      Error
        "Only one dump mode can be selected among --dump-dot/--dump-dot-short/--dump-automata/--dump-product/--dump-obligations-map/--dump-prune-reasons"
    else if eval_trace <> None
            && (dump_dot <> None || dump_dot_short <> None
               || dump_automata <> None || dump_product <> None || dump_obligations_map <> None
               || dump_prune_reasons <> None || emit_kobj <> None || dump_kobj_summary <> None
               || dump_kobj_clauses <> None || dump_kobj_product <> None
               || dump_kobj_product_contracts <> None
               || dump_why3_vc <> None || dump_smt2 <> None
               || dump_ast_stage <> None || dump_ast_all <> None || output_file <> None || prove
               || wp_only)
    then Error "--eval-trace cannot be combined with dump/prove options"
    else if
      dump_dot = None && dump_dot_short = None && dump_automata = None
      && dump_product = None && dump_obligations_map = None && dump_prune_reasons = None
      && emit_kobj = None && dump_kobj_summary = None && dump_kobj_clauses = None
      && dump_kobj_product = None && dump_kobj_product_contracts = None
      && dump_why3_vc = None && dump_smt2 = None && dump_proof_traces_json = None
      && dump_native_unsat_core_json = None && dump_native_counterexample_json = None
      && output_file = None && (not prove)
      && not wp_only
      && eval_trace = None
    then Error "Why3 output requires --dump-why <file.why|-> (or use --prove)"
    else if dump_proof_traces_json = None && dump_native_unsat_core_json = None
            && dump_native_counterexample_json = None
            && (proof_traces_failed_only || proof_traces_fast
               || proof_trace_goal_index <> None)
    then
      Error
        "--proof-traces-failed-only/--proof-traces-fast/--proof-trace-goal-index require --dump-proof-traces-json, --dump-native-unsat-core-json or --dump-native-counterexample-json"
    else if dump_native_unsat_core_json <> None && proof_trace_goal_index = None then
      Error "--dump-native-unsat-core-json requires --proof-trace-goal-index"
    else if dump_native_counterexample_json <> None && proof_trace_goal_index = None then
      Error "--dump-native-counterexample-json requires --proof-trace-goal-index"
    else Ok ()
  in
  match validate () with
  | Error msg -> `Error (false, msg)
  | Ok () ->
      let dump_ast_stage =
        match dump_ast_stage with
        | None -> Ok None
        | Some stage -> Stage_names.of_string stage |> Result.map (fun s -> Some s)
      in
      begin match dump_ast_stage with
      | Error msg -> `Error (false, msg)
      | Ok dump_ast_stage ->
          let _ = dump_ast_stage in
          let _ = dump_ast_out in
          if eval_trace <> None then (
            let trace_text_res =
              match eval_trace with
              | None -> Ok ""
              | Some "-" -> Ok (read_all_stdin ())
              | Some path -> (
                  try
                    let ic = open_in path in
                    let n = in_channel_length ic in
                    let text = really_input_string ic n in
                    close_in ic;
                    Ok text
                  with exn -> Error ("Cannot read eval trace file: " ^ Printexc.to_string exn))
            in
            match trace_text_res with
            | Error msg -> `Error (false, msg)
            | Ok trace_text -> (
                match
                  Engine_service.eval_pass ~engine:Engine_service.V2 ~input_file:file ~trace_text
                    ~with_state:eval_with_state ~with_locals:eval_with_locals
                with
                | Error err -> `Error (false, Pipeline.error_to_string err)
                | Ok out ->
                    (match eval_out with
                    | None | Some "-" -> print_endline out
                    | Some path -> Io.write_text path out);
                    `Ok ()))
          else
            let v2_supported =
              dump_json = None && dump_json_stable = None && dump_ast = None
              && dump_ast_all = None && not dump_ast_stable && not check_ast && not wp_only
              && not smoke_tests && not debug_contract_ids
            in
            if not v2_supported then
              `Error
                ( false,
                  "The v1 path has been removed. Unsupported options for v2: ast/json/check/smoke/debug/wp-only."
                )
            else (
              let write_target out text =
                match out with
                | "-" -> print_string text
                | path -> Io.write_text path text
              in
              match
                (dump_dot, dump_dot_short, dump_automata, dump_product, dump_obligations_map, dump_prune_reasons)
              with
              | _ when dump_kobj_summary <> None || dump_kobj_clauses <> None || dump_kobj_product <> None || dump_kobj_product_contracts <> None -> (
                  let out, render =
                    match (dump_kobj_summary, dump_kobj_clauses, dump_kobj_product, dump_kobj_product_contracts) with
                    | Some out, None, None, None -> (out, Kairos_object.render_summary)
                    | None, Some out, None, None -> (out, Kairos_object.render_clauses)
                    | None, None, Some out, None -> (out, Kairos_object.render_product)
                    | None, None, None, Some out -> (out, Kairos_object.render_product_contracts)
                    | _ -> failwith "unreachable kobj dump selection"
                  in
                  let obj_result =
                    if Filename.check_suffix file ".kobj" then
                      Kairos_object.read_file ~path:file
                    else
                      match Engine_service.compile_object ~engine:Engine_service.V2 ~input_file:file with
                      | Ok obj -> Ok obj
                      | Error e -> Error (Pipeline.error_to_string e)
                  in
                  match obj_result with
                  | Error msg -> `Error (false, msg)
                  | Ok obj ->
                      write_target out (render obj ^ "\n");
                      `Ok ())
              | _ when emit_kobj <> None -> (
                  match Engine_service.compile_object ~engine:Engine_service.V2 ~input_file:file with
                  | Error e -> `Error (false, Pipeline.error_to_string e)
                  | Ok obj ->
                      let out = Option.get emit_kobj in
                      (match Kairos_object.write_file ~path:out obj with
                      | Ok () -> `Ok ()
                      | Error msg -> `Error (false, msg)))
              | Some out, None, None, None, None, None
              | None, Some out, None, None, None, None -> (
                  match
                    Engine_service.instrumentation_pass ~engine:Engine_service.V2 ~generate_png:false
                      ~input_file:file
                  with
                  | Error e -> `Error (false, Pipeline.error_to_string e)
                  | Ok o ->
                      let dot_path = if Filename.check_suffix out ".dot" then out else out ^ ".dot" in
                      write_target dot_path o.dot_text;
                      let labels_path =
                        if Filename.check_suffix dot_path ".dot" then
                          Filename.chop_suffix dot_path ".dot" ^ ".labels"
                        else dot_path ^ ".labels"
                      in
                      write_target labels_path o.labels_text;
                      `Ok ())
              | None, None, Some out, None, None, None -> (
                  match
                    Engine_service.instrumentation_pass ~engine:Engine_service.V2 ~generate_png:false
                      ~input_file:file
                  with
                  | Error e -> `Error (false, Pipeline.error_to_string e)
                  | Ok o ->
                      write_target out (o.guarantee_automaton_text ^ "\n\n" ^ o.assume_automaton_text);
                      `Ok ())
              | None, None, None, Some out, None, None -> (
                  match
                    Engine_service.instrumentation_pass ~engine:Engine_service.V2 ~generate_png:false
                      ~input_file:file
                  with
                  | Error e -> `Error (false, Pipeline.error_to_string e)
                  | Ok o ->
                      write_target out o.product_text;
                      `Ok ())
              | None, None, None, None, Some out, None -> (
                  match
                    Engine_service.instrumentation_pass ~engine:Engine_service.V2 ~generate_png:false
                      ~input_file:file
                  with
                  | Error e -> `Error (false, Pipeline.error_to_string e)
                  | Ok o ->
                      write_target out o.obligations_map_text;
                      `Ok ())
              | None, None, None, None, None, Some out -> (
                  match
                    Engine_service.instrumentation_pass ~engine:Engine_service.V2 ~generate_png:false
                      ~input_file:file
                  with
                  | Error e -> `Error (false, Pipeline.error_to_string e)
                  | Ok o ->
                      write_target out o.prune_reasons_text;
                      `Ok ())
              | _ when dump_proof_traces_json <> None -> (
                  let cfg : Pipeline.config =
                    {
                      input_file = file;
                      prover;
                      prover_cmd;
                      wp_only = false;
                      smoke_tests = false;
                      timeout_s;
                      selected_goal_index = proof_trace_goal_index;
                      compute_proof_diagnostics = true;
                      prefix_fields = false;
                      why_translation_mode = why_mode;
                      prove = true;
                      generate_vc_text = not proof_traces_fast;
                      generate_smt_text = not proof_traces_fast;
                      generate_monitor_text = not proof_traces_fast;
                      generate_dot_png = false;
                    }
                  in
                  match Engine_service.run ~engine:Engine_service.V2 cfg with
                  | Error e -> `Error (false, Pipeline.error_to_string e)
                  | Ok outputs ->
                      let mapped = Lsp_app.map_outputs outputs in
                      let selected =
                        mapped.proof_traces
                        |> List.filter (fun (trace : Lsp_protocol.proof_trace) ->
                               if proof_traces_failed_only then
                                 trace.status <> "valid" && trace.status <> "pending"
                               else true)
                      in
                      let out = Option.get dump_proof_traces_json in
                      let emit_json oc =
                        output_string oc "[\n";
                        List.iteri
                          (fun idx trace ->
                            if idx > 0 then output_string oc ",\n";
                            Yojson.Safe.pretty_to_channel oc (Lsp_protocol.yojson_of_proof_trace trace))
                          selected;
                        output_string oc "\n]\n"
                      in
                      (if out = "-" then emit_json stdout
                       else
                         let oc = open_out out in
                         Fun.protect
                           ~finally:(fun () -> close_out_noerr oc)
                           (fun () -> emit_json oc));
                      `Ok ())
              | _ when dump_native_unsat_core_json <> None -> (
                  let cfg : Pipeline.config =
                    {
                      input_file = file;
                      prover;
                      prover_cmd;
                      wp_only = false;
                      smoke_tests = false;
                      timeout_s;
                      selected_goal_index = proof_trace_goal_index;
                      compute_proof_diagnostics = false;
                      prefix_fields = false;
                      why_translation_mode = why_mode;
                      prove = false;
                      generate_vc_text = false;
                      generate_smt_text = false;
                      generate_monitor_text = false;
                      generate_dot_png = false;
                    }
                  in
                  match Engine_service.run ~engine:Engine_service.V2 cfg with
                  | Error e -> `Error (false, Pipeline.error_to_string e)
                  | Ok outputs ->
                      let goal_index = Option.get proof_trace_goal_index in
                      let payload =
                        match
                          Why_prove.native_unsat_core_for_goal ~timeout:timeout_s ~prover
                            ~text:outputs.why_text ~goal_index ()
                        with
                        | None -> `Null
                        | Some core ->
                            `Assoc
                              [
                                ("solver", `String core.solver);
                                ("goal_index", `Int goal_index);
                                ("hypothesis_ids", `List (List.map (fun hid -> `Int hid) core.hypothesis_ids));
                                ("smt_text", `String core.smt_text);
                              ]
                      in
                      let out = Option.get dump_native_unsat_core_json in
                      (match out with
                      | "-" -> Yojson.Safe.pretty_to_channel stdout payload; print_newline ()
                      | path -> Yojson.Safe.to_file path payload);
                      `Ok ())
              | _ when dump_native_counterexample_json <> None -> (
                  let cfg : Pipeline.config =
                    {
                      input_file = file;
                      prover;
                      prover_cmd;
                      wp_only = false;
                      smoke_tests = false;
                      timeout_s;
                      selected_goal_index = proof_trace_goal_index;
                      compute_proof_diagnostics = false;
                      prefix_fields = false;
                      why_translation_mode = why_mode;
                      prove = false;
                      generate_vc_text = false;
                      generate_smt_text = false;
                      generate_monitor_text = false;
                      generate_dot_png = false;
                    }
                  in
                  match Engine_service.run ~engine:Engine_service.V2 cfg with
                  | Error e -> `Error (false, Pipeline.error_to_string e)
                  | Ok outputs ->
                      let goal_index = Option.get proof_trace_goal_index in
                      let payload =
                        match
                          Why_prove.native_solver_probe_for_goal ~timeout:timeout_s ~prover
                            ~text:outputs.why_text ~goal_index ()
                        with
                        | None -> `Null
                        | Some probe ->
                            `Assoc
                              [
                                ("solver", `String probe.solver);
                                ("goal_index", `Int goal_index);
                                ("status", `String probe.status);
                                ( "detail",
                                  match probe.detail with Some d -> `String d | None -> `Null );
                                ( "model_text",
                                  match probe.model_text with Some d -> `String d | None -> `Null );
                                ("smt_text", `String probe.smt_text);
                              ]
                      in
                      let out = Option.get dump_native_counterexample_json in
                      (match out with
                      | "-" -> Yojson.Safe.pretty_to_channel stdout payload; print_newline ()
                      | path -> Yojson.Safe.to_file path payload);
                      `Ok ())
              | _ ->
                  let cfg : V2_pipeline.config =
                    {
                      input_file = file;
                      dump_why = output_file;
                      dump_why3_vc;
                      dump_smt2;
                      why_translation_mode = why_mode;
                      prove;
                      prover;
                      prover_cmd;
                    }
                  in
                  (match V2_pipeline.run cfg with Ok () -> `Ok () | Error msg -> `Error (false, msg)))
      end

let cmd =
  let open Arg in
  let file =
    let doc = "Input OBC file." in
    required & pos 0 (some string) None & info [] ~docv:"FILE" ~doc
  in
  let dump_dot =
    value
    & opt (some string) None
    & info [ "dump-dot" ] ~docv:"FILE" ~doc:"Generate DOT with node ids and <file>.labels output."
  in
  let dump_dot_short =
    value
    & opt (some string) None
    & info [ "dump-dot-short" ] ~docv:"FILE" ~doc:"Alias of --dump-dot."
  in
  let dump_automata =
    value
    & opt (some string) None
    & info [ "dump-automata" ] ~docv:"FILE"
        ~doc:"Dump guarantee+assume automata (pure/runtime diagnostics text)."
  in
  let dump_product =
    value
    & opt (some string) None
    & info [ "dump-product" ] ~docv:"FILE"
        ~doc:"Dump reachable product Prog x A x G diagnostics (text)."
  in
  let dump_obligations_map =
    value
    & opt (some string) None
    & info [ "dump-obligations-map" ] ~docv:"FILE"
        ~doc:"Dump mapping from transitions to generated coherency obligations (text)."
  in
  let dump_prune_reasons =
    value
    & opt (some string) None
    & info [ "dump-prune-reasons" ] ~docv:"FILE"
        ~doc:"Dump prune reason counters used while exploring product compatibility."
  in
  let dump_why3_vc =
    value
    & opt (some string) None
    & info [ "dump-why3-vc" ] ~docv:"FILE" ~doc:"Dump Why3 VCs (after split/simplify)."
  in
  let dump_smt2 =
    value
    & opt (some string) None
    & info [ "dump-smt2" ] ~docv:"FILE" ~doc:"Dump SMT-LIB tasks sent to the solver."
  in
  let emit_kobj =
    value
    & opt (some string) None
    & info [ "emit-kobj" ] ~docv:"FILE"
        ~doc:"Compile the input source into a backend-agnostic .kobj object file."
  in
  let dump_kobj_summary =
    value
    & opt (some string) None
    & info [ "dump-kobj-summary" ] ~docv:"FILE"
        ~doc:
          "Dump a human-readable summary of a .kobj object to FILE (or '-' for stdout). If INPUT is a .kairos file, compile it first."
  in
  let dump_kobj_clauses =
    value
    & opt (some string) None
    & info [ "dump-kobj-clauses" ] ~docv:"FILE"
        ~doc:
          "Dump all kernel clauses from a .kobj object to FILE (or '-' for stdout). If INPUT is a .kairos file, compile it first."
  in
  let dump_kobj_product =
    value
    & opt (some string) None
    & info [ "dump-kobj-product" ] ~docv:"FILE"
        ~doc:
          "Dump product states/steps from a .kobj object to FILE (or '-' for stdout). If INPUT is a .kairos file, compile it first."
  in
  let dump_kobj_product_contracts =
    value
    & opt (some string) None
    & info [ "dump-kobj-product-contracts" ] ~docv:"FILE"
        ~doc:
          "Dump the product automaton followed by one proof contract per useful product step to FILE (or '-' for stdout). If INPUT is a .kairos file, compile it first."
  in
  let dump_json =
    value
    & opt (some string) None
    & info [ "dump-json" ] ~docv:"FILE"
        ~doc:"Dump internal AST as JSON (contracts stage) to file or '-' for stdout."
  in
  let dump_json_stable =
    value
    & opt (some string) None
    & info [ "dump-json-stable" ] ~docv:"FILE"
        ~doc:"Dump stable AST JSON (contracts stage) to file or '-' for stdout."
  in
  let dump_proof_traces_json =
    value
    & opt (some string) None
    & info [ "dump-proof-traces-json" ] ~docv:"FILE"
        ~doc:
          "Run proof and dump structured proof traces/explanations as JSON to FILE or '-' for stdout."
  in
  let dump_native_unsat_core_json =
    value
    & opt (some string) None
    & info [ "dump-native-unsat-core-json" ] ~docv:"FILE"
        ~doc:
          "On one focused goal, dump the native solver unsat core as JSON to FILE or '-' for stdout (null if unavailable)."
  in
  let dump_native_counterexample_json =
    value
    & opt (some string) None
    & info [ "dump-native-counterexample-json" ] ~docv:"FILE"
        ~doc:
          "On one focused goal, dump the native solver status/model probe as JSON to FILE or '-' for stdout (null if unavailable)."
  in
  let proof_traces_failed_only =
    value
    & flag
    & info [ "proof-traces-failed-only" ]
        ~doc:"With --dump-proof-traces-json, keep only non-proved goals."
  in
  let proof_traces_fast =
    value
    & flag
    & info [ "proof-traces-fast" ]
        ~doc:
          "With --dump-proof-traces-json, skip VC/SMT/monitor text materialization to bound heavy cases (trace spans to VC/SMT may be absent)."
  in
  let proof_trace_goal_index =
    value
    & opt (some int) None
    & info [ "proof-trace-goal-index" ] ~docv:"N"
        ~doc:
          "With --dump-proof-traces-json, focus diagnosis on one split goal index N (0-based)."
  in
  let dump_ast =
    value
    & opt (some dump_ast_conv) None
    & info [ "dump-ast" ] ~docv:"STAGE:FILE"
        ~doc:
          "Dump AST after stage: parsed|automaton|contracts|instrumentation|obc to file or '-' for stdout."
  in
  let dump_ast_all =
    value
    & opt (some string) None
    & info [ "dump-ast-all" ] ~docv:"DIR" ~doc:"Dump all AST stages as JSON into DIR."
  in
  let dump_ast_stable =
    value & flag & info [ "dump-ast-stable" ] ~doc:"Use stable JSON for --dump-ast/--dump-ast-all."
  in
  let check_ast =
    value & flag & info [ "check-ast" ] ~doc:"Run AST invariant checks after each stage."
  in
  let output_file =
    value
    & opt (some string) None
    & info [ "dump-why" ] ~docv:"FILE" ~doc:"Dump Why3 to file (or '-' for stdout)."
  in
  let prove = value & flag & info [ "prove" ] ~doc:"Run why3 prove on the generated output." in
  let prover =
    value & opt string "z3"
    & info [ "prover" ] ~docv:"NAME" ~doc:"Prover for --prove (default: z3)."
  in
  let prover_cmd =
    value
    & opt (some string) None
    & info [ "prover-cmd" ] ~docv:"CMD" ~doc:"Override prover command used by Why3 (advanced)."
  in
  let timeout_s =
    value
    & opt int 5
    & info [ "timeout-s" ] ~docv:"SECONDS" ~doc:"Timeout per proof goal in seconds (default: 5)."
  in
  let why_mode =
    value
    & opt why_mode_conv Pipeline.Why_mode_no_automata
    & info [ "why-mode" ] ~docv:"MODE"
        ~doc:"Why translation mode: no-automata (default) or monitor."
  in
  let wp_only =
    value & flag
    & info [ "wp-only" ] ~doc:"Compute verification conditions but do not call a prover."
  in
  let smoke_tests =
    value & flag
    & info [ "smoke-tests" ]
        ~doc:
          "Inject smoke obligations (ensure false) to detect inconsistent assumptions/hypotheses."
  in
  let eval_trace =
    value
    & opt (some string) None
    & info [ "eval-trace" ] ~docv:"FILE"
        ~doc:
          "Evaluate the source program on a trace file ('-' for stdin). Formats auto-detected: x=v lines, CSV (header+rows), or JSONL objects."
  in
  let eval_out =
    value
    & opt (some string) None
    & info [ "eval-out" ] ~docv:"FILE"
        ~doc:"Write evaluator output to FILE ('-' or omitted: stdout)."
  in
  let eval_with_state =
    value & flag
    & info [ "eval-with-state" ] ~doc:"Include current state in evaluator output."
  in
  let eval_with_locals =
    value & flag
    & info [ "eval-with-locals" ] ~doc:"Include locals in evaluator output."
  in
  let debug_contract_ids =
    value & flag
    & info [ "debug-contract-ids" ]
        ~doc:
          "Add debug ids/origins for transition contracts in OBC+ and Why3 outputs (rid/wid tags)."
  in
  let log_level =
    value
    & opt log_level_conv (Some Logs.Info)
    & info [ "log-level" ] ~docv:"LEVEL" ~doc:"Log level (quiet|error|warning|info|debug|app)."
  in
  let log_file =
    value
    & opt (some string) None
    & info [ "log-file" ] ~docv:"FILE" ~doc:"Write logs to FILE instead of stderr."
  in
  let doc = "Translate OBC to Why3 and run verification passes." in
  let info = Cmd.info "kairos" ~version:"0.1" ~doc in
  Cmd.v info
    Term.(
      ret
       (const run $ dump_dot $ dump_dot_short $ dump_automata
       $ dump_product $ dump_obligations_map $ dump_prune_reasons $ dump_why3_vc $ dump_smt2 $ emit_kobj
       $ dump_kobj_summary $ dump_kobj_clauses $ dump_kobj_product $ dump_kobj_product_contracts
       $ dump_json $ dump_json_stable $ dump_proof_traces_json $ dump_native_unsat_core_json
       $ dump_native_counterexample_json $ proof_traces_failed_only
       $ proof_traces_fast $ proof_trace_goal_index $ dump_ast $ dump_ast_all $ dump_ast_stable
       $ check_ast $ output_file $ prove $ prover $ prover_cmd $ timeout_s $ why_mode $ wp_only
       $ smoke_tests $ eval_trace $ eval_out $ eval_with_state $ eval_with_locals
       $ debug_contract_ids $ log_level $ log_file $ file))

let run () = exit (Cmd.eval cmd)
