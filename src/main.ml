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
open Contract_link

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

let json_escape (s:string) : string =
  let b = Buffer.create (String.length s) in
  String.iter
    (function
      | '\"' -> Buffer.add_string b "\\\""
      | '\\' -> Buffer.add_string b "\\\\"
      | '\n' -> Buffer.add_string b "\\n"
      | '\r' -> Buffer.add_string b "\\r"
      | '\t' -> Buffer.add_string b "\\t"
      | c when Char.code c < 0x20 ->
          Buffer.add_string b (Printf.sprintf "\\u%04x" (Char.code c))
      | c -> Buffer.add_char b c)
    s;
  Buffer.contents b

let dump_program_json ~(out:string option) (p:program) : unit =
  let payload = show_program p |> json_escape in
  let json = Printf.sprintf "{\"program\":\"%s\"}" payload in
  match out with
  | None -> print_endline json
  | Some path ->
      let oc = open_out path in
      output_string oc json;
      output_char oc '\n';
      close_out oc

let () =
  let dump_dot = ref None in
  let dump_dot_labels = ref None in
  let dump_obc = ref None in
  let no_prefix = ref true in
  let show_help = ref false in
  let prove = ref false in
  let prover = ref "z3" in
  let output_file = ref None in
  let dump_json = ref None in
  let naive_automaton = ref false in
  let files = ref [] in
  let usage =
    "Usage: obc2why3\n" ^
    "                [--dump-dot <file.dot>]\n" ^
    "                [--dump-dot-labels <file.dot>]\n" ^
    "                [--dump-json <file.json>|-]\n" ^
    "                [--dump-obc <file.obc+>]\n" ^
    "                [-o <file.why>]\n" ^
    "                [--prove --prover <name>] <file.obc>\n" ^
    "Options:\n" ^
    "  --help               Show this help message\n" ^
    "  --no-prefix          Do not prefix vars fields with the module name (default)\n" ^
    "  --dump-dot           Generate DOT for the monitor residual graph only\n" ^
    "                       (writes node/edge labels to <file>.labels)\n" ^
    "  --dump-dot-labels    Generate DOT with full node/edge labels\n" ^
    "  --naive-automaton    Use naive automaton construction (no BDD constraints)\n" ^
    "  --dump-json          Dump internal AST as JSON to file (or - for stdout)\n" ^
    "  --dump-obc           Dump augmented OBC (monitor-instrumented) to file\n" ^
    "  -o <file.why>        Write generated Why3 to this file\n" ^
    "  --prove              Run why3 prove on the generated output\n" ^
    "  --prover <name>      Prover for --prove (default: z3)\n"
  in
  let i = ref 1 in
  while !i < Array.length Sys.argv do
    match Sys.argv.(!i) with
    | "--help" ->
        show_help := true;
        incr i
    | "--no-prefix" ->
        no_prefix := true;
        incr i
    | "--dump-dot" ->
        if !i + 1 >= Array.length Sys.argv then (
          prerr_endline "Missing argument for --dump-dot";
          exit 1
        ) else (
          dump_dot := Some Sys.argv.(!i + 1);
          i := !i + 2
        )
    | "--dump-dot-labels" ->
        if !i + 1 >= Array.length Sys.argv then (
          prerr_endline "Missing argument for --dump-dot-labels";
          exit 1
        ) else (
          dump_dot_labels := Some Sys.argv.(!i + 1);
          i := !i + 2
        )
    | "--dump-obc" ->
        if !i + 1 >= Array.length Sys.argv then (
          prerr_endline "Missing argument for --dump-obc";
          exit 1
        ) else (
          dump_obc := Some Sys.argv.(!i + 1);
          i := !i + 2
        )
    | "--prove" ->
        prove := true;
        incr i
    | "--dump-json" ->
        if !i + 1 >= Array.length Sys.argv then (
          prerr_endline "Missing argument for --dump-json";
          exit 1
        ) else (
          dump_json := Some Sys.argv.(!i + 1);
          i := !i + 2
        )
    | "--naive-automaton" ->
        naive_automaton := true;
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
  match List.rev !files with
  | [file] ->
      let p = parse_file file |> List.map ensure_next_requires in
      Automaton_core.set_naive_automaton !naive_automaton;
      if (!dump_dot <> None || !dump_dot_labels <> None || !dump_obc <> None)
         && (!prove || !output_file <> None) then (
        prerr_endline "--dump-dot/--dump-obc cannot be combined with --prove or -o";
        exit 1
      );
      if !dump_obc <> None && (!dump_dot <> None || !dump_dot_labels <> None) then (
        prerr_endline "--dump-obc cannot be combined with --dump-dot or --dump-dot-labels";
        exit 1
      );
      if !dump_dot <> None && !dump_dot_labels <> None then (
        prerr_endline "--dump-dot and --dump-dot-labels are mutually exclusive";
        exit 1
      );
      begin
        match !dump_json with
        | None -> ()
        | Some "-" -> dump_program_json ~out:None p
        | Some path -> dump_program_json ~out:(Some path) p
      end;
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
          let action = "" in
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
      begin match !dump_dot, !dump_dot_labels, !dump_obc with
      | Some out_file, None, None
      | None, Some out_file, None ->
          let show_labels = !dump_dot_labels <> None in
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
          let dot, labels = Dot.dot_monitor_program ~show_labels p in
          write residual_file dot;
          if not show_labels then (
            let label_file =
              if Filename.check_suffix residual_file ".dot" then
                Filename.remove_extension residual_file ^ ".labels"
              else
                residual_file ^ ".labels"
            in
            write label_file labels
          );
      | None, None, Some out_file ->
          let ensure_ext path =
            if Filename.check_suffix path ".obc+" then path
            else if Filename.check_suffix path ".obc" then path ^ "+"
            else path ^ ".obc+"
          in
          let path = ensure_ext out_file in
          let out = Emit_obc.compile_program_monitor p in
          let oc = open_out path in
          output_string oc out;
          close_out oc
      | None, None, None ->
          let out =
            Monitor_emit.compile_program_monitor
              ~prefix_fields:(not !no_prefix)
              p
          in
          output_and_maybe_prove out
      | _ -> ()
      end
  | _ ->
      prerr_endline usage;
      exit 1
