(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *---------------------------------------------------------------------------*)

open Cmdliner

let docs_general = Manpage.s_common_options
let docs_proof = "PROOF"
let docs_graph = "GRAPH DUMPS"
let docs_text = "TEXT EXPORTS"
let docs_codegen = "CODE GENERATION"
let why3_proof = "WHY3"
let docs_frontend = "FRONTEND"

open Cli_types

module Pipeline = Kairos_engine.Api.Contract

let proof_encoding_parser s =
  match Pipeline.proof_encoding_of_string s with
  | Some encoding -> Ok encoding
  | None ->
      Error
        (`Msg
          (Printf.sprintf
             "unsupported proof encoding '%s' (available: explicit-product)" s))

let proof_encoding_printer fmt encoding =
  Format.pp_print_string fmt (Pipeline.string_of_proof_encoding encoding)

let proof_encoding_conv =
  Cmdliner.Arg.conv (proof_encoding_parser, proof_encoding_printer)

let cmd =
  let file =
    let doc = "Input Kairos file." in
    Arg.(required & pos 0 (some string) None & info [] ~docs:docs_general ~docv:"FILE" ~doc)
  in
  let check_frontend =
    Arg.(
      value & flag
      & info [ "check-frontend" ] ~docs:docs_frontend
          ~doc:"Parse and lower the input without building automata or proof obligations.")
  in
  let prove =
    Arg.(
      value & flag
      & info [ "prove" ] ~docs:docs_proof
          ~doc:
            "Run the prover on generated Why3 obligations. Proof artifacts are emitted only \
             when explicit dump options are passed.")
  in
  let dump_automata =
    Arg.(
      value & opt (some string) None
      & info [ "dump-automata" ] ~docs:docs_graph ~docv:"FILE"
          ~doc:"Dump guarantee+assume automata text.")
  in
  let dump_product =
    Arg.(
      value & opt (some string) None
      & info [ "dump-product" ] ~docs:docs_graph ~docv:"FILE"
          ~doc:"Dump product automaton text.")
  in
  let dump_canonical =
    Arg.(
      value & opt (some string) None
      & info [ "dump-canonical" ] ~docs:docs_graph ~docv:"FILE"
          ~doc:
            "Dump the canonical proof-step structure as FILE.dot plus FILE.txt side artifacts.")
  in
  let dump_automata_short =
    Arg.(
      value & opt (some string) None
      & info [ "dump-automata-short" ] ~docs:docs_graph ~docv:"FILE"
          ~doc:"Dump guarantee+assume automata text, plus short DOT side files without embedded formula legends.")
  in
  let dump_canonical_short =
    Arg.(
      value & opt (some string) None
      & info [ "dump-canonical-short" ] ~docs:docs_graph ~docv:"FILE"
          ~doc:
            "Dump the canonical proof-step structure as a short FILE.dot plus FILE.txt side artifacts.")
  in
  let dump_obligations_map =
    Arg.(
      value & opt (some string) None
      & info [ "dump-obligations-map" ] ~docs:docs_text ~docv:"FILE"
          ~doc:"Dump mapping from transitions to generated clauses.")
  in
  let dump_surface =
    Arg.(
      value & opt (some string) None
      & info [ "dump-surface" ] ~docs:docs_frontend ~docv:"FILE"
          ~doc:"Dump the parser surface AST before frontend elaboration.")
  in
  let dump_elaborated =
    Arg.(
      value & opt (some string) None
      & info [ "dump-elaborated" ] ~docs:docs_frontend ~docv:"FILE"
          ~doc:"Dump the frontend-elaborated AST passed to model lowering.")
  in
  let dump_normalized_program =
    Arg.(
      value & opt (some string) None
      & info [ "dump-normalized-program" ] ~docs:docs_text ~docv:"FILE"
          ~doc:"Dump the normalized program used by the pipeline.")
  in
  let dump_ir_pretty =
    Arg.(
      value & opt (some string) None
      & info [ "dump-ir-pretty" ] ~docs:docs_text ~docv:"FILE"
          ~doc:"Dump the full IR in canonical readable format.")
  in
  let dump_cost_report =
    Arg.(
      value & opt (some string) None
      & info [ "dump-cost-report" ] ~docs:docs_text ~docv:"FILE"
          ~doc:
            "Dump a JSON cost report from source, automata, product summaries, proof kernel, and generated WhyML.")
  in
  let emit_c =
    Arg.(
      value & opt (some string) None
      & info [ "emit-c" ] ~docs:docs_codegen ~docv:"DIR"
          ~doc:"Generate portable C99 sources into DIR.")
  in
  let dump_timings =
    Arg.(
      value & opt (some string) None
      & info [ "dump-timings" ] ~docs:docs_text ~docv:"FILE"
          ~doc:
            "Dump per-run metrics as CSV key/value lines (timings, graph/canonical counts, obligation taxonomy).")
  in
  let dump_goals =
    Arg.(
      value & opt (some string) None
      & info [ "dump-goals" ] ~docs:docs_proof ~docv:"FILE"
          ~doc:"Dump proof goal statuses and prover times as CSV.")
  in
  let dump_failed_smt =
    Arg.(
      value & flag
      & info [ "dump-failed-smt" ] ~docs:docs_proof
          ~doc:"Dump SMT-LIB scripts for goals that are not proved during --prove.")
  in
  let dump_why =
    Arg.(
      value & opt (some string) None
      & info [ "dump-why" ] ~docs:why3_proof ~docv:"FILE"
          ~doc:"Dump Why3 program to FILE (or '-' for stdout).")
  in
  let dump_why3_vc =
    Arg.(
      value & opt (some string) None
      & info [ "dump-why3-vc" ] ~docs:why3_proof ~docv:"FILE" ~doc:"Dump Why3 VC tasks to FILE.")
  in
  let dump_smt2 =
    Arg.(
      value & opt (some string) None
      & info [ "dump-smt2" ] ~docs:why3_proof ~docv:"FILE" ~doc:"Dump SMT-LIB tasks to FILE.")
  in
  let timeout_s =
    Arg.(
      value & opt int 10
      & info [ "timeout-s" ] ~docs:docs_proof ~docv:"SECONDS"
          ~doc:"Per-goal prover timeout in seconds for --prove and Why3 obligation dumps.")
  in
  let proof_jobs =
    Arg.(
      value & opt int (Kairos_engine.Api.default_proof_jobs ())
      & info [ "proof-jobs" ] ~docs:docs_proof ~docv:"JOBS"
          ~doc:
            "Maximum number of Why3 prover calls to keep in flight. The default \
             is derived from the CPU topology and available parallelism. With \
             --stop-on-first-nonvalid, Kairos uses one job to keep strict \
             first-failure semantics.")
  in
  let proof_encoding =
    Arg.(
      value
      & opt proof_encoding_conv Pipeline.default_proof_encoding
      & info [ "proof-encoding" ] ~docs:docs_proof ~docv:"ENCODING"
          ~doc:
            "Select the proof-obligation encoding. Currently available: explicit-product.")
  in
  let stop_on_first_nonvalid =
    Arg.(
      value & flag
      & info [ "stop-on-first-nonvalid" ] ~docs:docs_proof
          ~doc:
            "Stop proving after the first goal whose prover status is not valid/proved. Useful with --dump-goals for focused diagnostics.")
  in
  let no_proof_optimizations =
    Arg.(
      value & flag
      & info [ "no-proof-optimizations" ] ~docs:docs_proof
          ~doc:
            "Disable proof-generation optimizations. This selects the reference pipeline shape used for Rocq alignment checks.")
  in
  let no_proof_grouping =
    Arg.(
      value & flag
      & info [ "no-proof-grouping" ] ~docs:docs_proof
          ~doc:
            "Disable the optimization that groups public non-W guarantees into a single proof node.")
  in
  let no_why3_product_step_grouping =
    Arg.(
      value & flag
      & info [ "no-why3-product-step-grouping" ] ~docs:docs_proof
          ~doc:
            "Disable grouping of safe product-step Why3 helpers by executable \
             transition. Bad-guarantee exclusion helpers are kept individual.")
  in
  let cli_args_term =
    (* Cmdliner still declares options one by one, but we now assemble them into
       a record before entering the operational logic. *)
    let make_cli_args file check_frontend prove timeout_s proof_jobs proof_encoding
        stop_on_first_nonvalid no_proof_optimizations no_proof_grouping
        no_why3_product_step_grouping
        dump_automata dump_product dump_canonical dump_automata_short
        dump_canonical_short dump_obligations_map dump_surface dump_elaborated
        dump_normalized_program dump_ir_pretty dump_cost_report emit_c dump_timings
        dump_goals dump_failed_smt dump_why dump_why3_vc dump_smt2 =
      {
        file;
        check_frontend;
        prove;
        timeout_s;
        proof_jobs;
        proof_encoding;
        stop_on_first_nonvalid;
        no_proof_optimizations;
        no_proof_grouping;
        no_why3_product_step_grouping;
        dump_automata;
        dump_product;
        dump_canonical;
        dump_automata_short;
        dump_canonical_short;
        dump_obligations_map;
        dump_surface;
        dump_elaborated;
        dump_normalized_program;
        dump_ir_pretty;
        dump_cost_report;
        emit_c;
        dump_timings;
        dump_goals;
        dump_failed_smt;
        dump_why;
        dump_why3_vc;
        dump_smt2;
      }
    in
    Term.(
      const make_cli_args $ file $ check_frontend $ prove $ timeout_s
      $ proof_jobs $ proof_encoding $ stop_on_first_nonvalid $ no_proof_optimizations
      $ no_proof_grouping $ no_why3_product_step_grouping
      $ dump_automata $ dump_product $ dump_canonical $ dump_automata_short
      $ dump_canonical_short $ dump_obligations_map $ dump_surface
      $ dump_elaborated $ dump_normalized_program $ dump_ir_pretty
      $ dump_cost_report $ emit_c $ dump_timings $ dump_goals $ dump_failed_smt
      $ dump_why $ dump_why3_vc $ dump_smt2)
  in
  let term = Term.(ret (const Cli_runtime.eval_cli $ cli_args_term)) in
  let man =
    [
      `S Manpage.s_description;
      `P "Kairos command line interface.";
      `S docs_proof;
      `S docs_frontend;
      `S docs_graph;
      `S docs_text;
      `S docs_codegen;
      `S Manpage.s_common_options;
    ]
  in
  let info =
    Cmd.info "kairos" ~doc:"Command-line adapter for the Kairos engine"
      ~man
  in
  Cmd.v info term

let run () = exit (Cmd.eval cmd)

let () = run ()
