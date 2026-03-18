open Cmdliner

let write_target out text =
  match out with
  | "-" -> print_string text
  | path -> Io.write_text path text

let write_file dir name text =
  let path = Filename.concat dir name in
  Io.write_text path text

let ensure_dir dir =
  if not (Sys.file_exists dir) then
    ignore (Sys.command (Printf.sprintf "mkdir -p %s" (Filename.quote dir)))

let run dump_dot dump_dot_short dump_automata dump_product dump_obligations_map
    dump_prune_reasons dump_why dump_why3_vc dump_smt2 dump_ir_dir prove prover
    prover_cmd file =
  let () =
    match dump_ir_dir with
    | None -> ()
    | Some dir -> (
        ensure_dir dir;
        match Engine_service.dump_ir_nodes ~engine:Engine_service.V2 ~input_file:file with
        | Error err ->
            Printf.eprintf "dump-ir-dir error: %s\n" (Pipeline.error_to_string err)
        | Ok ir ->
            List.iter
              (fun (raw : Kairos_ir.raw_node) ->
                let name = raw.node_name in
                write_file dir (name ^ ".raw.kir") (Kairos_ir_render.render_raw_node raw))
              ir.raw_ir_nodes;
            List.iter
              (fun (ann : Kairos_ir.annotated_node) ->
                let name = ann.raw.node_name in
                write_file dir (name ^ ".annotated.kir")
                  (Kairos_ir_render.render_annotated_node ann);
                write_file dir (name ^ ".annotated.dot")
                  (Kairos_ir_dot.dot_of_annotated_node ann))
              ir.annotated_ir_nodes;
            List.iter
              (fun (ver : Kairos_ir.verified_node) ->
                let name = ver.node_name in
                write_file dir (name ^ ".verified.kir")
                  (Kairos_ir_render.render_verified_node ver);
                write_file dir (name ^ ".verified.dot")
                  (Kairos_ir_dot.dot_of_verified_node ver))
              ir.verified_ir_nodes;
            List.iter
              (fun (ker : Product_kernel_ir.node_ir) ->
                let name = ker.reactive_program.node_name in
                write_file dir (name ^ ".kernel.dot")
                  (Kairos_ir_dot.dot_of_kernel_node_ir ker))
              ir.kernel_ir_nodes)
  in
  let dump_mode_count =
    List.fold_left (fun acc b -> if b then acc + 1 else acc) 0
      [
        dump_dot <> None;
        dump_dot_short <> None;
        dump_automata <> None;
        dump_product <> None;
        dump_obligations_map <> None;
        dump_prune_reasons <> None;
      ]
  in
  if
    (dump_dot <> None || dump_dot_short <> None || dump_automata <> None || dump_product <> None
   || dump_obligations_map <> None || dump_prune_reasons <> None)
    && (prove || dump_why <> None || dump_why3_vc <> None || dump_smt2 <> None)
  then
    `Error
      ( false,
        "--dump-dot/--dump-automata/--dump-product/--dump-obligations-map/--dump-prune-reasons cannot be combined with --prove or Why3 dump options"
      )
  else if dump_mode_count > 1 then
    `Error
      ( false,
        "Only one dump mode can be selected among --dump-dot/--dump-dot-short/--dump-automata/--dump-product/--dump-obligations-map/--dump-prune-reasons"
      )
  else
    match
      (dump_dot, dump_dot_short, dump_automata, dump_product, dump_obligations_map, dump_prune_reasons)
    with
    | Some out, None, None, None, None, None
    | None, Some out, None, None, None, None -> (
        match
          Engine_service.instrumentation_pass ~engine:Engine_service.V2 ~generate_png:false
            ~input_file:file
        with
        | Error err -> `Error (false, Pipeline.error_to_string err)
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
        | Error err -> `Error (false, Pipeline.error_to_string err)
        | Ok o ->
            write_target out (o.guarantee_automaton_text ^ "\n\n" ^ o.assume_automaton_text);
            `Ok ())
    | None, None, None, Some out, None, None -> (
        match
          Engine_service.instrumentation_pass ~engine:Engine_service.V2 ~generate_png:false
            ~input_file:file
        with
        | Error err -> `Error (false, Pipeline.error_to_string err)
        | Ok o ->
            write_target out o.product_text;
            `Ok ())
    | None, None, None, None, Some out, None -> (
        match
          Engine_service.instrumentation_pass ~engine:Engine_service.V2 ~generate_png:false
            ~input_file:file
        with
        | Error err -> `Error (false, Pipeline.error_to_string err)
        | Ok o ->
            write_target out o.obligations_map_text;
            `Ok ())
    | None, None, None, None, None, Some out -> (
        match
          Engine_service.instrumentation_pass ~engine:Engine_service.V2 ~generate_png:false
            ~input_file:file
        with
        | Error err -> `Error (false, Pipeline.error_to_string err)
        | Ok o ->
            write_target out o.prune_reasons_text;
            `Ok ())
    | _ ->
        let cfg : V2_pipeline.config =
          {
            input_file = file;
            dump_why;
            dump_why3_vc;
            dump_smt2;
            prove;
            prover;
            prover_cmd;
          }
        in
        match V2_pipeline.run cfg with
        | Ok () -> `Ok ()
        | Error msg -> `Error (false, msg)

let cmd =
  let file =
    let doc = "Input Kairos file." in
    Arg.(required & pos 0 (some string) None & info [] ~docv:"FILE" ~doc)
  in
  let dump_dot =
    Arg.(
      value
      & opt (some string) None
      & info [ "dump-dot" ] ~docv:"FILE" ~doc:"Generate DOT with node ids and <file>.labels output.")
  in
  let dump_dot_short =
    Arg.(value & opt (some string) None & info [ "dump-dot-short" ] ~docv:"FILE" ~doc:"Alias of --dump-dot.")
  in
  let dump_automata =
    Arg.(
      value
      & opt (some string) None
      & info [ "dump-automata" ] ~docv:"FILE"
          ~doc:"Dump guarantee+assume automata (pure/runtime diagnostics text).")
  in
  let dump_product =
    Arg.(
      value
      & opt (some string) None
      & info [ "dump-product" ] ~docv:"FILE"
          ~doc:"Dump reachable product Prog x A x G diagnostics (text).")
  in
  let dump_obligations_map =
    Arg.(
      value
      & opt (some string) None
      & info [ "dump-obligations-map" ] ~docv:"FILE"
          ~doc:"Dump mapping from transitions to generated coherency clauses (text).")
  in
  let dump_prune_reasons =
    Arg.(
      value
      & opt (some string) None
      & info [ "dump-prune-reasons" ] ~docv:"FILE"
          ~doc:"Dump prune reason counters used while exploring product compatibility.")
  in
  let dump_why =
    Arg.(
      value
      & opt (some string) None
      & info [ "dump-why" ] ~docv:"FILE" ~doc:"Dump Why3 program to FILE (or '-' for stdout).")
  in
  let dump_why3_vc =
    Arg.(
      value
      & opt (some string) None
      & info [ "dump-why3-vc" ] ~docv:"FILE" ~doc:"Dump Why3 VC tasks to FILE.")
  in
  let dump_smt2 =
    Arg.(
      value
      & opt (some string) None
      & info [ "dump-smt2" ] ~docv:"FILE" ~doc:"Dump SMT-LIB tasks to FILE.")
  in
  let dump_ir_dir =
    Arg.(
      value
      & opt (some string) None
      & info [ "dump-ir-dir" ] ~docv:"DIR"
          ~doc:
            "Dump raw/annotated/verified IR (.kir) and DOT graphs (.dot) to DIR. \
             Compatible with --prove and Why3 options.")
  in
  let prove = Arg.(value & flag & info [ "prove" ] ~doc:"Run prover on generated Why3 obligations.") in
  let prover =
    Arg.(
      value
      & opt string "z3"
      & info [ "prover" ] ~docv:"NAME" ~doc:"Prover for --prove (default: z3).")
  in
  let prover_cmd =
    Arg.(
      value
      & opt (some string) None
      & info [ "prover-cmd" ] ~docv:"CMD" ~doc:"Override prover command.")
  in
  let term =
    Term.(
      ret
        (const run $ dump_dot $ dump_dot_short $ dump_automata $ dump_product $ dump_obligations_map
       $ dump_prune_reasons $ dump_why $ dump_why3_vc $ dump_smt2 $ dump_ir_dir
       $ prove $ prover $ prover_cmd $ file))
  in
  Cmd.v
    (Cmd.info "kairos_v2" ~version:"0.1" ~doc:"Kairos refactoring pipeline (v2, architecture-driven)")
    term

let run () = exit (Cmd.eval cmd)
