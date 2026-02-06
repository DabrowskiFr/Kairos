open Cmdliner

let dump_ast_conv =
  let parse s =
    match String.split_on_char ':' s with
    | [stage; out] when stage <> "" && out <> "" -> Ok (stage, out)
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

let run
    dump_dot
    dump_dot_short
    dump_obc
    dump_why3_vc
    dump_smt2
    dump_json
    dump_json_stable
    dump_json_attrs
    dump_ast
    dump_ast_all
    dump_ast_stable
    dump_ast_attrs
    check_ast
    output_file
    prove
    prover
    prover_cmd
    wp_only
    log_level
    log_file
    file =
  Log.setup ~level:log_level ~log_file;
  let dump_ast_stage, dump_ast_out =
    match dump_ast, dump_json, dump_json_stable with
    | Some (stage, out), None, None -> (Some stage, Some out)
    | None, Some out, None -> (Some "contracts", Some out)
    | None, None, Some out -> (Some "contracts", Some out)
    | None, None, None -> (None, None)
    | _ -> (None, None)
  in
  let validate () =
    if dump_ast <> None && dump_json <> None then
      Error "--dump-json and --dump-ast are mutually exclusive"
    else if dump_json <> None && dump_json_stable <> None then
      Error "--dump-json and --dump-json-stable are mutually exclusive"
    else if dump_json_stable = None && dump_json_attrs then
      Error "--dump-json-attrs requires --dump-json-stable"
    else if dump_ast_all <> None && dump_ast_stable = false && dump_ast_attrs then
      Error "--dump-ast-attrs requires --dump-ast-stable"
    else if dump_ast <> None && dump_ast_all <> None then
      Error "--dump-ast and --dump-ast-all are mutually exclusive"
    else if (dump_json <> None || dump_json_stable <> None) && dump_ast_all <> None then
      Error "--dump-json and --dump-ast-all are mutually exclusive"
    else if (dump_dot <> None || dump_dot_short <> None || dump_obc <> None
             || dump_ast_stage <> None || dump_ast_all <> None)
            && (prove || wp_only || output_file <> None) then
      Error "--dump-dot/--dump-obc/--dump-ast cannot be combined with --prove or --dump-why"
    else if dump_obc <> None
            && (dump_dot <> None || dump_dot_short <> None
                || dump_ast_stage <> None || dump_ast_all <> None
                || dump_why3_vc <> None || dump_smt2 <> None) then
      Error "--dump-obc cannot be combined with --dump-dot/--dump-dot-short or --dump-ast"
    else if (dump_why3_vc <> None || dump_smt2 <> None)
            && (dump_dot <> None || dump_dot_short <> None
                || dump_obc <> None || dump_ast_stage <> None
                || dump_ast_all <> None) then
      Error "--dump-why3-vc/--dump-smt2 cannot be combined with --dump-dot/--dump-obc/--dump-ast"
    else if dump_dot <> None && dump_dot_short <> None then
      Error "--dump-dot and --dump-dot-short are mutually exclusive"
    else if dump_dot = None && dump_dot_short = None && dump_obc = None
            && dump_why3_vc = None && dump_smt2 = None
            && output_file = None && not prove && not wp_only then
      Error "Why3 output requires --dump-why <file.why|-> (or use --prove)"
    else Ok ()
  in
  match validate () with
  | Error msg -> `Error (false, msg)
  | Ok () ->
      let dump_ast_stage =
        match dump_ast_stage with
        | None -> Ok None
        | Some stage ->
            Stage_names.of_string stage
            |> Result.map (fun s -> Some s)
      in
      begin match dump_ast_stage with
      | Error msg -> `Error (false, msg)
      | Ok dump_ast_stage ->
          let stages_cfg =
            {
              Stages.dump_dot = dump_dot;
              dump_dot_short = dump_dot_short;
              dump_obc = dump_obc;
              dump_why3_vc = dump_why3_vc;
              dump_smt2 = dump_smt2;
              dump_ast_stage;
              dump_ast_out;
              dump_ast_all = dump_ast_all;
              dump_ast_stable = dump_ast_stable || dump_json_stable <> None;
              dump_ast_include_attrs = dump_json_attrs || dump_ast_attrs;
              check_ast = check_ast;
              output_file = output_file;
              prove = prove;
              prover = prover;
              prover_cmd = prover_cmd;
              wp_only = wp_only;
              prefix_fields = false;
              input_file = file;
            }
          in
          begin match Stages.run stages_cfg with
          | Ok () -> `Ok ()
          | Error msg -> `Error (false, msg)
          end
      end

let cmd =
  let open Arg in
  let file =
    let doc = "Input OBC file." in
    required & pos 0 (some string) None & info [] ~docv:"FILE" ~doc
  in
  let dump_dot =
    value & opt (some string) None & info ["dump-dot"] ~docv:"FILE"
      ~doc:"Generate DOT with node ids and <file>.labels output."
  in
  let dump_dot_short =
    value & opt (some string) None & info ["dump-dot-short"] ~docv:"FILE"
      ~doc:"Alias of --dump-dot."
  in
  let dump_obc =
    value & opt (some string) None & info ["dump-obc"] ~docv:"FILE"
      ~doc:"Dump augmented OBC (monitor-instrumented)."
  in
  let dump_why3_vc =
    value & opt (some string) None & info ["dump-why3-vc"] ~docv:"FILE"
      ~doc:"Dump Why3 VCs (after split/simplify)."
  in
  let dump_smt2 =
    value & opt (some string) None & info ["dump-smt2"] ~docv:"FILE"
      ~doc:"Dump SMT-LIB tasks sent to the solver."
  in
  let dump_json =
    value & opt (some string) None & info ["dump-json"] ~docv:"FILE"
      ~doc:"Dump internal AST as JSON (contracts stage) to file or '-' for stdout."
  in
  let dump_json_stable =
    value & opt (some string) None & info ["dump-json-stable"] ~docv:"FILE"
      ~doc:"Dump stable AST JSON (contracts stage) to file or '-' for stdout."
  in
  let dump_json_attrs =
    value & flag & info ["dump-json-attrs"]
      ~doc:"Include attrs in --dump-json-stable output."
  in
  let dump_ast =
    value & opt (some dump_ast_conv) None & info ["dump-ast"] ~docv:"STAGE:FILE"
      ~doc:"Dump AST after stage: parsed|automaton|contracts|monitor|obc to file or '-' for stdout."
  in
  let dump_ast_all =
    value & opt (some string) None & info ["dump-ast-all"] ~docv:"DIR"
      ~doc:"Dump all AST stages as JSON into DIR."
  in
  let dump_ast_stable =
    value & flag & info ["dump-ast-stable"]
      ~doc:"Use stable JSON for --dump-ast/--dump-ast-all."
  in
  let dump_ast_attrs =
    value & flag & info ["dump-ast-attrs"]
      ~doc:"Include attrs in stable AST JSON dumps."
  in
  let check_ast =
    value & flag & info ["check-ast"]
      ~doc:"Run AST invariant checks after each stage."
  in
  let output_file =
    value & opt (some string) None & info ["dump-why"] ~docv:"FILE"
      ~doc:"Dump Why3 to file (or '-' for stdout)."
  in
  let prove =
    value & flag & info ["prove"] ~doc:"Run why3 prove on the generated output."
  in
  let prover =
    value & opt string "z3" & info ["prover"] ~docv:"NAME"
      ~doc:"Prover for --prove (default: z3)."
  in
  let prover_cmd =
    value & opt (some string) None & info ["prover-cmd"] ~docv:"CMD"
      ~doc:"Override prover command used by Why3 (advanced)."
  in
  let wp_only =
    value & flag & info ["wp-only"]
      ~doc:"Compute verification conditions but do not call a prover."
  in
  let log_level =
    value & opt log_level_conv (Some Logs.Info) & info ["log-level"] ~docv:"LEVEL"
      ~doc:"Log level (quiet|error|warning|info|debug|app)."
  in
  let log_file =
    value & opt (some string) None & info ["log-file"] ~docv:"FILE"
      ~doc:"Write logs to FILE instead of stderr."
  in
  let doc = "Translate OBC to Why3 and run verification passes." in
  let info = Cmd.info "obc2why3" ~version:"0.1" ~doc in
  Cmd.v info Term.(ret (const run
                        $ dump_dot
                        $ dump_dot_short
                        $ dump_obc
                        $ dump_why3_vc
                        $ dump_smt2
                        $ dump_json
                        $ dump_json_stable
                        $ dump_json_attrs
                        $ dump_ast
                        $ dump_ast_all
                        $ dump_ast_stable
                        $ dump_ast_attrs
                        $ check_ast
                        $ output_file
                        $ prove
                        $ prover
                        $ prover_cmd
                        $ wp_only
                        $ log_level
                        $ log_file
                        $ file))

let run () = exit (Cmd.eval cmd)
