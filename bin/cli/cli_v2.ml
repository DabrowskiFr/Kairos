open Cmdliner

let run dump_obc dump_obc_abstract dump_why dump_why3_vc dump_smt2 prove prover prover_cmd file =
  let cfg : V2_pipeline.config =
    {
      input_file = file;
      dump_obc;
      dump_obc_abstract;
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
  let dump_obc =
    Arg.(
      value
      & opt (some string) None
      & info [ "dump-obc" ] ~docv:"FILE" ~doc:"Dump augmented OBC to FILE (or '-' for stdout).")
  in
  let dump_obc_abstract =
    Arg.(
      value
      & flag
      & info [ "dump-obc-abstract" ]
          ~doc:"With --dump-obc, use abstract OBC rendering instead of legacy emitter.")
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
    Term.(ret (const run $ dump_obc $ dump_obc_abstract $ dump_why $ dump_why3_vc $ dump_smt2 $ prove $ prover $ prover_cmd $ file))
  in
  Cmd.v
    (Cmd.info "kairos_v2" ~version:"0.1" ~doc:"Kairos refactoring pipeline (v2, architecture-driven)")
    term

let run () = exit (Cmd.eval cmd)
