type cli_config = {
  dump_dot : string option;
  dump_dot_labels : string option;
  dump_obc : string option;
  no_prefix : bool;
  show_help : bool;
  prove : bool;
  prover : string;
  output_file : string option;
  dump_json : string option;
  dump_ast : (string * string) option;
  dump_ast_all : string option;
  trace : bool;
  files : string list;
}

let default_config = {
  dump_dot = None;
  dump_dot_labels = None;
  dump_obc = None;
  no_prefix = true;
  show_help = false;
  prove = false;
  prover = "z3";
  output_file = None;
  dump_json = None;
  dump_ast = None;
  dump_ast_all = None;
  trace = false;
  files = [];
}

let usage_text =
  "Usage: obc2why3\n" ^
  "                [--dump-dot <file.dot>]\n" ^
  "                [--dump-dot-labels <file.dot>]\n" ^
  "                [--dump-json <file.json>|-]\n" ^
  "                [--dump-obc <file.obc+>]\n" ^
  "                [--dump-ast <stage> <file|->]\n" ^
  "                [--dump-ast-all <dir>]\n" ^
  "                [--trace-stages]\n" ^
  "                [-o <file.why>]\n" ^
  "                [--prove --prover <name>] <file.obc>\n" ^
  "Options:\n" ^
  "  --help               Show this help message\n" ^
  "  --no-prefix          Do not prefix vars fields with the module name (default)\n" ^
  "  --dump-dot           Generate DOT for the monitor residual graph only\n" ^
  "                       (writes node/edge labels to <file>.labels)\n" ^
  "  --dump-dot-labels    Generate DOT with full node/edge labels\n" ^
  "  --dump-json          Dump internal AST as JSON to file (or - for stdout)\n" ^
  "  --dump-obc           Dump augmented OBC (monitor-instrumented) to file\n" ^
  "  --dump-ast <stage> <file|->\n" ^
  "                       Dump AST after stage: " ^
    (String.concat "|" (List.map Stage_names.to_string Stage_names.all)) ^ "\n" ^
  "  --dump-ast-all <dir> Dump all AST stages as JSON into <dir>\n" ^
  "  --trace-stages       Trace stage execution to stderr\n" ^
  "  -o <file.why>        Write generated Why3 to this file\n" ^
  "  --prove              Run why3 prove on the generated output\n" ^
  "  --prover <name>      Prover for --prove (default: z3)\n" ^
  "Examples:\n" ^
  "  obc2why3 --dump-dot out.dot input.obc\n" ^
  "  obc2why3 --dump-ast automaton - input.obc\n" ^
  "  obc2why3 --dump-ast-all out_ast input.obc\n" ^
  "  obc2why3 -o out.why input.obc\n"

let parse_args () : (cli_config, string) result =
  let argv = Sys.argv in
  let len = Array.length argv in
  let rec loop i cfg =
    if i >= len then Ok cfg
    else
      match argv.(i) with
      | "--help" -> loop (i + 1) { cfg with show_help = true }
      | "--no-prefix" -> loop (i + 1) { cfg with no_prefix = true }
      | "--dump-dot" ->
          if i + 1 >= len then Error "Missing argument for --dump-dot"
          else loop (i + 2) { cfg with dump_dot = Some argv.(i + 1) }
      | "--dump-dot-labels" ->
          if i + 1 >= len then Error "Missing argument for --dump-dot-labels"
          else loop (i + 2) { cfg with dump_dot_labels = Some argv.(i + 1) }
      | "--dump-obc" ->
          if i + 1 >= len then Error "Missing argument for --dump-obc"
          else loop (i + 2) { cfg with dump_obc = Some argv.(i + 1) }
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
      | "-o" ->
          if i + 1 >= len then Error "Missing argument for -o"
          else loop (i + 2) { cfg with output_file = Some argv.(i + 1) }
      | "--prover" ->
          if i + 1 >= len then Error "Missing argument for --prover"
          else loop (i + 2) { cfg with prover = argv.(i + 1) }
      | "--trace-stages" -> loop (i + 1) { cfg with trace = true }
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
  else if (cfg.dump_dot <> None || cfg.dump_dot_labels <> None || cfg.dump_obc <> None
           || cfg.dump_ast <> None || cfg.dump_ast_all <> None)
          && (cfg.prove || cfg.output_file <> None) then
    Error "--dump-dot/--dump-obc/--dump-ast cannot be combined with --prove or -o"
  else if cfg.dump_obc <> None
          && (cfg.dump_dot <> None || cfg.dump_dot_labels <> None
              || cfg.dump_ast <> None || cfg.dump_ast_all <> None) then
    Error "--dump-obc cannot be combined with --dump-dot, --dump-dot-labels, or --dump-ast"
  else if cfg.dump_dot <> None && cfg.dump_dot_labels <> None then
    Error "--dump-dot and --dump-dot-labels are mutually exclusive"
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
              dump_dot_labels = cfg.dump_dot_labels;
              dump_obc = cfg.dump_obc;
              dump_ast_stage;
              dump_ast_out;
              dump_ast_all = cfg.dump_ast_all;
              trace = cfg.trace;
              output_file = cfg.output_file;
              prove = cfg.prove;
              prover = cfg.prover;
              prefix_fields = not cfg.no_prefix;
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
