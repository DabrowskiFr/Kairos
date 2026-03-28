open Cmdliner

let write_target out text =
  match out with
  | "-" -> print_string text
  | path -> Artifact_io.write_text path text

let dot_dump_base (path : string) : string =
  if Filename.check_suffix path ".dot" then Filename.chop_suffix path ".dot" else path

let report_failed_goals (goals : Lsp_protocol.goal_info list) : string list =
  let failure_info (_, status, _, dump_path, source, vcid) =
    let status = String.lowercase_ascii status in
    if status <> "valid" && status <> "proved" && status <> "unknown" then
      Some (status, dump_path, source, vcid)
    else None
  in
  List.mapi
    (fun idx ((goal, _, time_s, _, _, _) as info) ->
      match failure_info info with
      | Some (status, dump_path, source, vcid) ->
          Some
            (Printf.sprintf "goal %d/%d failed: %s (source=%s%s%s, time=%.3fs)" (idx + 1)
               (List.length goals) goal source
               (match vcid with None -> "" | Some id -> ", vcid=" ^ id)
               (match dump_path with None -> "" | Some p -> ", dump=" ^ p)
               time_s)
      | None -> None)
    goals
  |> List.filter_map (fun x -> x)

let run dump_dot dump_dot_short dump_automata dump_product dump_obligations_map
    dump_prune_reasons dump_why dump_why3_vc dump_smt2 dump_kobj_summary
    dump_kobj_clauses dump_kobj_product prove prover prover_cmd file =
  let dump_mode_count =
    List.fold_left (fun acc b -> if b then acc + 1 else acc) 0
      [
        dump_dot <> None;
        dump_dot_short <> None;
        dump_automata <> None;
        dump_product <> None;
        dump_obligations_map <> None;
        dump_prune_reasons <> None;
        dump_kobj_summary <> None;
        dump_kobj_clauses <> None;
        dump_kobj_product <> None;
      ]
  in
  if
    (dump_dot <> None || dump_dot_short <> None || dump_automata <> None
   || dump_product <> None || dump_obligations_map <> None
      || dump_prune_reasons <> None || dump_kobj_summary <> None
      || dump_kobj_clauses <> None || dump_kobj_product <> None)
    && (prove || dump_why <> None || dump_why3_vc <> None || dump_smt2 <> None)
  then
    `Error
      ( false,
        "--dump-dot/--dump-automata/--dump-product/--dump-obligations-map/--dump-prune-reasons/--dump-kobj-* cannot be combined with --prove or Why3 dump options"
      )
  else if dump_mode_count > 1 then
    `Error
      ( false,
        "Only one dump mode can be selected among --dump-dot/--dump-dot-short/--dump-automata/--dump-product/--dump-obligations-map/--dump-prune-reasons/--dump-kobj-*"
      )
  else
    let instrumentation_req =
      {
        Lsp_protocol.input_file = file;
        generate_png = false;
        engine = Engine_service.string_of_engine Engine_service.Default;
      }
    in
    let why_req =
      {
        Lsp_protocol.input_file = file;
        prefix_fields = false;
        engine = Engine_service.string_of_engine Engine_service.Default;
      }
    in
    let oblig_req =
      {
        Lsp_protocol.input_file = file;
        prover;
        prefix_fields = false;
        engine = Engine_service.string_of_engine Engine_service.Default;
      }
    in
    let kobj_req =
      {
        Lsp_protocol.input_file = file;
        engine = Engine_service.string_of_engine Engine_service.Default;
      }
    in
    match
      ( dump_dot,
        dump_dot_short,
        dump_automata,
        dump_product,
        dump_obligations_map,
        dump_prune_reasons,
        dump_kobj_summary,
        dump_kobj_clauses,
        dump_kobj_product )
    with
    | Some out, None, None, None, None, None, None, None, None
    | None, Some out, None, None, None, None, None, None, None -> (
        match Lsp_backend.instrumentation_pass instrumentation_req with
        | Error msg -> `Error (false, msg)
        | Ok o ->
            let dot_path = if Filename.check_suffix out ".dot" then out else out ^ ".dot" in
            let dot_base = dot_dump_base dot_path in
            write_target dot_path o.dot_text;
            let labels_path =
              if Filename.check_suffix dot_path ".dot" then
                Filename.chop_suffix dot_path ".dot" ^ ".labels"
              else dot_path ^ ".labels"
            in
            write_target labels_path o.labels_text;
            write_target (dot_base ^ ".assume.dot") o.assume_automaton_dot;
            write_target (dot_base ^ ".guarantee.dot") o.guarantee_automaton_dot;
            write_target (dot_base ^ ".product.dot") o.product_dot;
            `Ok ())
    | None, None, Some out, None, None, None, None, None, None -> (
        match Lsp_backend.instrumentation_pass instrumentation_req with
        | Error msg -> `Error (false, msg)
        | Ok o ->
            write_target out (o.guarantee_automaton_text ^ "\n\n" ^ o.assume_automaton_text);
            `Ok ())
    | None, None, None, Some out, None, None, None, None, None -> (
        match Lsp_backend.instrumentation_pass instrumentation_req with
        | Error msg -> `Error (false, msg)
        | Ok o ->
            write_target out o.product_text;
            `Ok ())
    | None, None, None, None, Some out, None, None, None, None -> (
        match Lsp_backend.instrumentation_pass instrumentation_req with
        | Error msg -> `Error (false, msg)
        | Ok o ->
            write_target out o.obligations_map_text;
            `Ok ())
    | None, None, None, None, None, Some out, None, None, None -> (
        match Lsp_backend.instrumentation_pass instrumentation_req with
        | Error msg -> `Error (false, msg)
        | Ok o ->
            write_target out o.prune_reasons_text;
            `Ok ())
    | None, None, None, None, None, None, Some out, None, None -> (
        match Lsp_backend.kobj_summary kobj_req with
        | Error msg -> `Error (false, msg)
        | Ok text ->
            write_target out text;
            `Ok ())
    | None, None, None, None, None, None, None, Some out, None -> (
        match Lsp_backend.kobj_clauses kobj_req with
        | Error msg -> `Error (false, msg)
        | Ok text ->
            write_target out text;
            `Ok ())
    | None, None, None, None, None, None, None, None, Some out -> (
        match Lsp_backend.kobj_product kobj_req with
        | Error msg -> `Error (false, msg)
        | Ok text ->
            write_target out text;
            `Ok ())
    | _ ->
        if dump_why <> None && not prove && dump_why3_vc = None && dump_smt2 = None then (
          match Lsp_backend.why_pass why_req with
          | Error msg -> `Error (false, msg)
          | Ok out ->
              write_target (Option.get dump_why) out.why_text;
              `Ok ())
        else if dump_why = None && not prove && dump_why3_vc <> None && dump_smt2 = None then (
          match Lsp_backend.obligations_pass oblig_req with
          | Error msg -> `Error (false, msg)
          | Ok out ->
              write_target (Option.get dump_why3_vc) out.vc_text;
              `Ok ())
        else if dump_why = None && not prove && dump_why3_vc = None && dump_smt2 <> None then (
          match Lsp_backend.obligations_pass oblig_req with
          | Error msg -> `Error (false, msg)
          | Ok out ->
              write_target (Option.get dump_smt2) out.smt_text;
              `Ok ())
        else
          let cfg : Lsp_protocol.config =
            {
              input_file = file;
              engine = Engine_service.string_of_engine Engine_service.Default;
              prover;
              prover_cmd;
              wp_only = false;
              smoke_tests = false;
              timeout_s = 10;
              selected_goal_index = None;
              compute_proof_diagnostics = false;
              prefix_fields = false;
              prove;
              generate_vc_text = dump_why3_vc <> None;
              generate_smt_text = dump_smt2 <> None;
              generate_dot_png = false;
            }
          in
          match Lsp_backend.run ~engine:Engine_service.Default cfg with
          | Error msg -> `Error (false, msg)
          | Ok out ->
              Option.iter (fun path -> write_target path out.why_text) dump_why;
              Option.iter (fun path -> write_target path out.vc_text) dump_why3_vc;
              Option.iter (fun path -> write_target path out.smt_text) dump_smt2;
              if prove then
                let failures = report_failed_goals out.goals in
                if failures <> [] then
                  `Error (false, String.concat "\n" failures)
                else `Ok ()
              else `Ok ()

let cmd =
  let file =
    let doc = "Input Kairos file." in
    Arg.(required & pos 0 (some string) None & info [] ~docv:"FILE" ~doc)
  in
  let dump_dot =
    Arg.(
      value & opt (some string) None
      & info [ "dump-dot" ] ~docv:"FILE"
          ~doc:"Generate DOT bundle and specialized assume/guarantee/product DOT files.")
  in
  let dump_dot_short =
    Arg.(value & opt (some string) None & info [ "dump-dot-short" ] ~docv:"FILE" ~doc:"Alias of --dump-dot.")
  in
  let dump_automata =
    Arg.(
      value & opt (some string) None
      & info [ "dump-automata" ] ~docv:"FILE"
          ~doc:"Dump guarantee+assume automata text.")
  in
  let dump_product =
    Arg.(
      value & opt (some string) None
      & info [ "dump-product" ] ~docv:"FILE"
          ~doc:"Dump product automaton text.")
  in
  let dump_obligations_map =
    Arg.(
      value & opt (some string) None
      & info [ "dump-obligations-map" ] ~docv:"FILE"
          ~doc:"Dump mapping from transitions to generated clauses.")
  in
  let dump_prune_reasons =
    Arg.(
      value & opt (some string) None
      & info [ "dump-prune-reasons" ] ~docv:"FILE"
          ~doc:"Dump prune reason counters for product exploration.")
  in
  let dump_why =
    Arg.(
      value & opt (some string) None
      & info [ "dump-why" ] ~docv:"FILE"
          ~doc:"Dump Why3 program to FILE (or '-' for stdout).")
  in
  let dump_why3_vc =
    Arg.(
      value & opt (some string) None
      & info [ "dump-why3-vc" ] ~docv:"FILE" ~doc:"Dump Why3 VC tasks to FILE.")
  in
  let dump_smt2 =
    Arg.(
      value & opt (some string) None
      & info [ "dump-smt2" ] ~docv:"FILE" ~doc:"Dump SMT-LIB tasks to FILE.")
  in
  let dump_kobj_summary =
    Arg.(
      value & opt (some string) None
      & info [ "dump-kobj-summary" ] ~docv:"FILE" ~doc:"Dump kobj summary text.")
  in
  let dump_kobj_clauses =
    Arg.(
      value & opt (some string) None
      & info [ "dump-kobj-clauses" ] ~docv:"FILE" ~doc:"Dump kobj clauses text.")
  in
  let dump_kobj_product =
    Arg.(
      value & opt (some string) None
      & info [ "dump-kobj-product" ] ~docv:"FILE" ~doc:"Dump kobj product text.")
  in
  let prove =
    Arg.(value & flag & info [ "prove" ] ~doc:"Run prover on generated Why3 obligations.")
  in
  let prover =
    Arg.(
      value & opt string "z3"
      & info [ "prover" ] ~docv:"NAME" ~doc:"Prover for --prove (default: z3).")
  in
  let prover_cmd =
    Arg.(
      value & opt (some string) None
      & info [ "prover-cmd" ] ~docv:"CMD" ~doc:"Override prover command.")
  in
  let term =
    Term.(
      ret
        (const run $ dump_dot $ dump_dot_short $ dump_automata $ dump_product
       $ dump_obligations_map $ dump_prune_reasons $ dump_why $ dump_why3_vc
       $ dump_smt2 $ dump_kobj_summary $ dump_kobj_clauses $ dump_kobj_product
       $ prove $ prover $ prover_cmd $ file))
  in
  let info = Cmd.info "kairos" ~doc:"Minimal CLI backed by the Kairos LSP service layer" in
  Cmd.v info term

let run () = exit (Cmd.eval cmd)
