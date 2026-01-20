(*---------------------------------------------------------------------------
 * Tempo - synchronous runtime for OCaml
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

open Ast
open Whygen_passes

let parse_file (fn:string) : program =
  let ic = open_in fn in
  let lb = Lexing.from_channel ic in
  try
    let p = Parser.program Lexer.token lb in
    close_in ic; p
  with e ->
    let pos = lb.lex_curr_p in
    Printf.eprintf "Parse error at %s:%d:%d\n"
      pos.pos_fname pos.pos_lnum (pos.pos_cnum - pos.pos_bol);
    close_in_noerr ic;
    raise e

let () =
  let use_monitor = ref true in
  let monitor_dot = ref None in
  let monitor_no_prefix = ref true in
  let no_prefix = ref false in
  let show_help = ref false in
  let k_induction = ref false in
  let prove = ref false in
  let prover = ref "z3" in
  let vc_all = ref false in
  let output_file = ref None in
  let files = ref [] in
  let usage =
    "Usage: obc2why3 [--monitor] [--k-induction]\n" ^
    "                [--monitor-dot <file.dot>]\n" ^
    "                [-o <file.why>]\n" ^
    "                [--prove --prover <name>] <file.obc>\n" ^
    "Options:\n" ^
    "  --help               Show this help message\n" ^
    "  --monitor            Generate Why3 using a monitor state for residuals (default)\n" ^
    "  --monitor-no-prefix  Do not prefix vars fields with the module name (monitor mode, default)\n" ^
    "  --no-prefix          Do not prefix vars fields with the module name (monitor mode, default)\n" ^
    "  --monitor-dot        Generate DOT for the monitor residual graph and print Why3\n" ^
    "  -o <file.why>        Write generated Why3 to this file\n" ^
    "  --k-induction        Generate k-induction proof obligations for X^k under G\n" ^
    "  --prove              Run why3 prove on the generated output\n" ^
    "  -vc-all              Show results for all VCs (split VC)\n" ^
    "  --prover <name>      Prover for --prove (default: z3)\n"
  in
  let i = ref 1 in
  while !i < Array.length Sys.argv do
    match Sys.argv.(!i) with
    | "--help" ->
        show_help := true;
        incr i
    | "--monitor-no-prefix" ->
        monitor_no_prefix := true;
        incr i
    | "--no-prefix" ->
        no_prefix := true;
        incr i
    | "--monitor" ->
        use_monitor := true;
        incr i
    | "--monitor-dot" ->
        if !i + 1 >= Array.length Sys.argv then (
          prerr_endline "Missing argument for --monitor-dot";
          exit 1
        ) else (
          monitor_dot := Some Sys.argv.(!i + 1);
          i := !i + 2
        )
    | "--k-induction" ->
        k_induction := true;
        incr i
    | "--prove" ->
        prove := true;
        incr i
    | "-vc-all" ->
        vc_all := true;
        incr i
    | "-o" ->
        if !i + 1 >= Array.length Sys.argv then (
          prerr_endline "Missing argument for -o";
          exit 1
        ) else (
          output_file := Some Sys.argv.(!i + 1);
          i := !i + 2
        )
    | "--prover" ->
        if !i + 1 >= Array.length Sys.argv then (
          prerr_endline "Missing argument for --prover";
          exit 1
        ) else (
          prover := Sys.argv.(!i + 1);
          i := !i + 2
        )
    | arg when String.length arg > 0 && arg.[0] = '-' ->
        prerr_endline ("Unknown option: " ^ arg);
        exit 1
    | arg ->
        files := arg :: !files;
        incr i
  done;
  if !show_help then (
    print_string usage;
    exit 0
  );
  if !no_prefix then (
    monitor_no_prefix := true
  );
  match List.rev !files with
  | [file] ->
      let p = parse_file file |> add_post_for_next_pre_program in
      let output_and_maybe_prove out =
        let output_path =
          match !output_file with
          | Some path ->
              let oc = open_out path in
              output_string oc out;
              close_out oc;
              Some path
          | None -> None
        in
        if !prove then (
          let prove_path, remove_after =
            match output_path with
            | Some path -> (path, false)
            | None ->
                let tmp = Filename.temp_file "obc2why3_" ".why" in
                let oc = open_out tmp in
                output_string oc out;
                close_out oc;
                (tmp, true)
          in
          let action =
            if !vc_all then "-a split_vc "
            else ""
          in
          let cmd =
            Printf.sprintf "why3 prove -P %s -t 30 %s%s"
              !prover action (Filename.quote prove_path)
          in
          let status = Sys.command cmd in
          if remove_after then Sys.remove prove_path;
          if status <> 0 then exit status
        );
        if output_path = None then print_string out
      in
      begin match !monitor_dot with
      | Some out_file ->
          let residual_file =
            if Filename.check_suffix out_file ".dot"
            then out_file
            else out_file ^ ".dot"
          in
          let write path content =
            let oc = open_out path in
            output_string oc content;
            close_out oc
          in
          write residual_file (Whygen_emit_automaton.dot_monitor_program p);
          let out =
            Whygen_emit_automaton.compile_program_monitor
              ~k_induction:!k_induction
              ~prefix_fields:(not !monitor_no_prefix)
              p
          in
          output_and_maybe_prove out
      | None ->
          let out =
            if !use_monitor then
              Whygen_emit_automaton.compile_program_monitor
                ~k_induction:!k_induction
                ~prefix_fields:(not !monitor_no_prefix)
                p
            else
              Whygen_emit_automaton.compile_program_monitor
                ~k_induction:!k_induction
                ~prefix_fields:(not !monitor_no_prefix)
                p
          in
          output_and_maybe_prove out
      end
  | _ ->
      prerr_endline usage;
      exit 1
