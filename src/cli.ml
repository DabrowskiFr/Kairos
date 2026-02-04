type cli_config = {
  dump_dot : string option;
  dump_dot_short : string option;

  dump_obc : string option;
  dump_why3_vc : string option;
  dump_smt2 : string option;
  show_help : bool;
  prove : bool;
  prover : string;
  output_file : string option;
  dump_json : string option;
  dump_ast : (string * string) option;
  dump_ast_all : string option;
  files : string list;
  log_level : string;
  log_format : string;
  log_color : string;
  log_file : string option;
}

let default_config = {
  dump_dot = None;
  dump_dot_short = None;

  dump_obc = None;
  dump_why3_vc = None;
  dump_smt2 = None;
  show_help = false;
  prove = false;
  prover = "z3";
  output_file = None;
  dump_json = None;
  dump_ast = None;
  dump_ast_all = None;
  files = [];
  log_level = "normal";
  log_format = "pretty";
  log_color = "auto";
  log_file = None;
}

let usage_text =
  "Usage: obc2why3\n" ^
  "  [--dump-dot <file|->] [--dump-dot-short <file|->] [--dump-json <file|->]\n" ^
  "  [--dump-obc <file|->] [--dump-why <file|->] [--dump-ast <stage> <file|->]\n" ^
  "  [--dump-ast-all <dir>] [--dump-why3-vc <file|->] [--dump-smt2 <file|->]\n" ^
  "  [--log-level <quiet|normal|verbose|debug|trace>] [--log-format <pretty|json>]\n" ^
  "  [--log-color <auto|always|never>] [--log-file <path>] [--version]\n" ^
  "  [--prove --prover <name>] <file.obc>\n" ^
  "Options:\n" ^
  "  --help                           Show this help message\n" ^
  "  --dump-dot <file|->              Generate DOT with node ids and <file>.labels output\n" ^
  "  --dump-dot-short <file|->        Alias of --dump-dot\n" ^
  "  --dump-why3-vc <file|->          Dump Why3 VCs (after split/simplify)\n" ^
  "  --dump-smt2 <file|->             Dump SMT-LIB tasks sent to the solver\n" ^
  "  --dump-json <file|->             Dump internal AST as JSON to file (or - for stdout)\n" ^
  "  --dump-obc <file|->              Dump augmented OBC (monitor-instrumented) to file\n" ^
  "  --dump-why <file|->              Dump Why3 to file (or - for stdout)\n" ^
  "  --dump-ast <stage> <file|->      Dump AST after stage: " ^
    (String.concat "|" (List.map Stage_names.to_string Stage_names.ast_stages)) ^ "\n" ^
  "  --dump-ast-all <dir>             Dump all AST stages as JSON into <dir>\n" ^
  "  --version                        Show tool version\n" ^
  "  --log-level <level>              Log verbosity (quiet|normal|verbose|debug|trace)\n" ^
  "  --log-format <format>            Log format (pretty|json)\n" ^
  "  --log-color <mode>               Color mode (auto|always|never)\n" ^
  "  --log-file <path>                Write logs to file instead of stderr\n" ^
  "  --prove                          Run why3 prove on the generated output\n" ^
  "  --prover <name>                  Prover for --prove (default: z3)\n" ^
  "Examples:\n" ^
  "  obc2why3 --dump-dot out.dot input.obc\n" ^
  "  obc2why3 --dump-ast automaton - input.obc\n" ^
  "  obc2why3 --dump-ast-all out_ast input.obc\n" ^
  "  obc2why3 --dump-why out.why input.obc\n"

let parse_args () : (cli_config, string) result =
  let argv = Sys.argv in
  let len = Array.length argv in
  let rec loop i cfg =
    if i >= len then Ok cfg
    else
      match argv.(i) with
      | "--help" -> loop (i + 1) { cfg with show_help = true }
      | "--dump-dot" ->
          if i + 1 >= len then Error "Missing argument for --dump-dot"
          else loop (i + 2) { cfg with dump_dot = Some argv.(i + 1) }
      | "--dump-dot-short" ->
          if i + 1 >= len then Error "Missing argument for --dump-dot-short"
          else loop (i + 2) { cfg with dump_dot_short = Some argv.(i + 1) }
      | "--dump-obc" ->
          if i + 1 >= len then Error "Missing argument for --dump-obc"
          else loop (i + 2) { cfg with dump_obc = Some argv.(i + 1) }
      | "--dump-why3-vc" ->
          if i + 1 >= len then Error "Missing argument for --dump-why3-vc"
          else loop (i + 2) { cfg with dump_why3_vc = Some argv.(i + 1) }
      | "--dump-smt2" ->
          if i + 1 >= len then Error "Missing argument for --dump-smt2"
          else loop (i + 2) { cfg with dump_smt2 = Some argv.(i + 1) }
      | "--prove" -> loop (i + 1) { cfg with prove = true }
      | "--dump-json" ->
          if i + 1 >= len then Error "Missing argument for --dump-json"
          else loop (i + 2) { cfg with dump_json = Some argv.(i + 1) }
      | "--dump-ast" ->
          if i + 2 >= len then Error "Missing arguments for --dump-ast"
          else
            loop (i + 3)
              { cfg with dump_ast = Some (argv.(i + 1), argv.(i + 2)) }
      | "--dump-ast-all" ->
          if i + 1 >= len then Error "Missing argument for --dump-ast-all"
          else loop (i + 2) { cfg with dump_ast_all = Some argv.(i + 1) }
      | "--dump-why" ->
          if i + 1 >= len then Error "Missing argument for --dump-why"
          else loop (i + 2) { cfg with output_file = Some argv.(i + 1) }
      | "--prover" ->
          if i + 1 >= len then Error "Missing argument for --prover"
          else loop (i + 2) { cfg with prover = argv.(i + 1) }
      | "--version" ->
          print_endline "obc2why3 0.1";
          exit 0
      | "--log-level" ->
          if i + 1 >= len then Error "Missing argument for --log-level"
          else loop (i + 2) { cfg with log_level = argv.(i + 1) }
      | "--log-format" ->
          if i + 1 >= len then Error "Missing argument for --log-format"
          else loop (i + 2) { cfg with log_format = argv.(i + 1) }
      | "--log-color" ->
          if i + 1 >= len then Error "Missing argument for --log-color"
          else loop (i + 2) { cfg with log_color = argv.(i + 1) }
      | "--log-file" ->
          if i + 1 >= len then Error "Missing argument for --log-file"
          else loop (i + 2) { cfg with log_file = Some argv.(i + 1) }
      | arg when String.length arg > 0 && arg.[0] = '-' ->
          Error ("Unknown option: " ^ arg)
      | arg -> loop (i + 1) { cfg with files = cfg.files @ [arg] }
  in
  loop 1 default_config

let validate_config (cfg:cli_config) : (cli_config, string) result =
  if cfg.show_help then Ok cfg
  else if cfg.files = [] then
    Error "Missing input file. Provide a .obc file as the last argument."
  else if (cfg.dump_json <> None && cfg.dump_ast <> None)
       || (cfg.dump_json <> None && cfg.dump_ast_all <> None)
       || (cfg.dump_ast <> None && cfg.dump_ast_all <> None) then
    Error "--dump-json/--dump-ast/--dump-ast-all are mutually exclusive"
  else if (cfg.dump_dot <> None || cfg.dump_dot_short <> None || cfg.dump_obc <> None
           || cfg.dump_ast <> None || cfg.dump_ast_all <> None)
          && (cfg.prove || cfg.output_file <> None) then
    Error "--dump-dot/--dump-obc/--dump-ast cannot be combined with --prove or --dump-why"
  else if cfg.dump_obc <> None
          && (cfg.dump_dot <> None || cfg.dump_dot_short <> None
              || cfg.dump_ast <> None || cfg.dump_ast_all <> None
              || cfg.dump_why3_vc <> None || cfg.dump_smt2 <> None) then
    Error "--dump-obc cannot be combined with --dump-dot/--dump-dot-short or --dump-ast"
  else if (cfg.dump_why3_vc <> None || cfg.dump_smt2 <> None)
          && (cfg.dump_dot <> None || cfg.dump_dot_short <> None
              || cfg.dump_obc <> None || cfg.dump_ast <> None
              || cfg.dump_ast_all <> None) then
    Error "--dump-why3-vc/--dump-smt2 cannot be combined with --dump-dot/--dump-obc/--dump-ast"
  else if cfg.dump_dot <> None && cfg.dump_dot_short <> None then
    Error "--dump-dot and --dump-dot-short are mutually exclusive"
  else if cfg.dump_dot = None && cfg.dump_dot_short = None && cfg.dump_obc = None
          && cfg.dump_why3_vc = None && cfg.dump_smt2 = None
          && cfg.output_file = None && not cfg.prove then
    Error "Why3 output requires --dump-why <file.why|-> (or use --prove)"
  else Ok cfg

let run () =
  match parse_args () with
  | Error msg ->
      prerr_endline msg;
      prerr_endline usage_text;
      exit 1
  | Ok cfg ->
      let cfg =
        match validate_config cfg with
        | Ok cfg -> cfg
        | Error msg ->
            prerr_endline msg;
            prerr_endline usage_text;
            exit 1
      in
      if cfg.show_help then (
        print_string usage_text;
        exit 0
      );
      let log_level =
        match Logger.parse_level cfg.log_level with
        | Ok v -> v
        | Error msg -> prerr_endline msg; exit 1
      in
      let log_format =
        match Logger.parse_format cfg.log_format with
        | Ok v -> v
        | Error msg -> prerr_endline msg; exit 1
      in
      let log_color =
        match Logger.parse_color cfg.log_color with
        | Ok v -> v
        | Error msg -> prerr_endline msg; exit 1
      in
      let log_output =
        match cfg.log_file with
        | None -> stderr
        | Some path -> open_out path
      in
      Logger.set_config { level = log_level; format = log_format; color = log_color; output = log_output };
      let file = List.hd (List.rev cfg.files) in
      let dump_ast_stage, dump_ast_out =
        match cfg.dump_ast, cfg.dump_json with
        | Some (stage, out), None -> (Some stage, Some out)
        | None, Some out -> (Some "contracts", Some out)
        | None, None -> (None, None)
        | Some _, Some _ -> (None, None)
      in
      let dump_ast_stage =
        match dump_ast_stage with
        | None -> Ok None
        | Some stage ->
            Stage_names.of_string stage
            |> Result.map (fun s -> Some s)
      in
      let stages_config =
        dump_ast_stage
        |> Result.map (fun dump_ast_stage ->
            {
              Stages.dump_dot = cfg.dump_dot;
              dump_dot_short = cfg.dump_dot_short;

              dump_obc = cfg.dump_obc;
              dump_why3_vc = cfg.dump_why3_vc;
              dump_smt2 = cfg.dump_smt2;
              dump_ast_stage;
              dump_ast_out;
              dump_ast_all = cfg.dump_ast_all;
              output_file = cfg.output_file;
              prove = cfg.prove;
              prover = cfg.prover;
              prefix_fields = false;
              input_file = file;
            })
      in
      begin match stages_config with
      | Error msg ->
          prerr_endline msg;
          exit 1
      | Ok stages_cfg ->
          begin match Stages.run stages_cfg with
          | Ok () -> ()
          | Error msg ->
              prerr_endline msg;
              exit 1
          end
      end
