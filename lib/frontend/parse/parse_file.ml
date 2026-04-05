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

open Ast
module A = Ast

let read_all (fn : string) : string =
  let ic = open_in_bin fn in
  let len = in_channel_length ic in
  let s = really_input_string ic len in
  close_in ic;
  s

let parse_source_file_with_info (fn : string) : Source_file.t * Stage_info.parse_info =
  let file_text = read_all fn in
  let file_hash = Digest.to_hex (Digest.string file_text) in
  let ic = open_in fn in
  let lb = Sedlexing.Utf8.from_channel ic in
  Sedlexing.set_filename lb fn;
  try
    let last_two = ref [] in
    let start_pos = { Lexing.pos_fname = fn; pos_lnum = 1; pos_bol = 0; pos_cnum = 0 } in
    let module I = Parser.MenhirInterpreter in
    let push_lexeme s =
      if s <> "" then
        last_two :=
          match !last_two with [] -> [ s ] | [ a ] -> [ a; s ] | [ _; b ] -> [ b; s ] | _ -> [ s ]
    in
    let supplier () =
      let tok = Lexer.token lb in
      push_lexeme (Lexer.last_lexeme ());
      let startp, endp = Sedlexing.lexing_positions lb in
      (tok, startp, endp)
    in
    let handle_error checkpoint_input _checkpoint_error =
      let pos, _ = Sedlexing.lexing_positions lb in
      let col = pos.pos_cnum - pos.pos_bol + 1 in
      let lexeme =
        let s = Lexer.last_lexeme () in
        if s = "" then "<eof>" else s
      in
      let expected =
        let tokens =
          List.filter
            (fun (_name, tok) -> I.acceptable checkpoint_input tok pos)
            Lexer.expected_tokens
          |> List.map fst
        in
        if tokens = [] then "" else " Expected: " ^ String.concat ", " tokens
      in
      let context =
        match !last_two with
        | [ a; b ] -> Printf.sprintf " after '%s' before '%s'" a b
        | [ a ] -> Printf.sprintf " after '%s'" a
        | _ -> ""
      in
      raise
        (Failure
           (Printf.sprintf "Parse error at %s:%d:%d near '%s'%s.%s" pos.pos_fname pos.pos_lnum col
              lexeme context expected))
    in
    let checkpoint = Parser.Incremental.source_file start_pos in
    let p = I.loop_handle_undo (fun v -> v) handle_error supplier checkpoint in
    close_in ic;
    let source = p in
    let info =
      {
        Stage_info.source_path = Some fn;
        Stage_info.text_hash = Some file_hash;
        Stage_info.parse_errors = [];
        Stage_info.warnings = [];
      }
    in
    (source, info)
  with
  | Lexer.Lexing_error msg ->
      let pos, _ = Sedlexing.lexing_positions lb in
      let col = pos.pos_cnum - pos.pos_bol + 1 in
      close_in_noerr ic;
      raise
        (Failure (Printf.sprintf "Lexing error at %s:%d:%d: %s" pos.pos_fname pos.pos_lnum col msg))
  | e ->
      let pos, _ = Sedlexing.lexing_positions lb in
      Printf.eprintf "Parse error at %s:%d:%d\n" pos.pos_fname pos.pos_lnum
        (pos.pos_cnum - pos.pos_bol);
      close_in_noerr ic;
      raise e

let parse_file_with_info (fn : string) : Ast.program * Stage_info.parse_info =
  let source, info = parse_source_file_with_info fn in
  (source.nodes, info)

let parse_file (fn : string) : Ast.program =
  let source, _info = parse_source_file_with_info fn in
  source.nodes
