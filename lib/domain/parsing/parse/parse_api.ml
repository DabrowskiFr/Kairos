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

type import_decl = {
  import_path : string;
  import_loc : Loc.loc option;
}

type source = {
  imports : import_decl list;
  nodes : Ast.program;
}

let imported_paths (parsed_source : source) : string list =
  List.map (fun decl -> decl.import_path) parsed_source.imports

type parse_error = {
  loc : Loc.loc option;
  message : string;
}

type parse_info = {
  source_path : string option;
  text_hash : string option;
  parse_errors : parse_error list;
  warnings : string list;
}

let parse_source_text_with_info ~(filename : string) ~(text : string) : source * parse_info =
  let file_text = text in
  let file_hash = Digest.to_hex (Digest.string file_text) in
  let lb = Sedlexing.Utf8.from_string file_text in
  Sedlexing.set_filename lb filename;
  try
    let last_two = ref [] in
    let start_pos = { Lexing.pos_fname = filename; pos_lnum = 1; pos_bol = 0; pos_cnum = 0 } in
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
    let imports_raw, nodes = I.loop_handle_undo (fun v -> v) handle_error supplier checkpoint in
    let imports =
      List.map
        (fun (import_path, import_loc) -> { import_path; import_loc })
        imports_raw
    in
    let parsed_source = { imports; nodes } in
    let info =
      {
        source_path = Some filename;
        text_hash = Some file_hash;
        parse_errors = [];
        warnings = [];
      }
    in
    (parsed_source, info)
  with
  | Lexer.Lexing_error msg ->
      let pos, _ = Sedlexing.lexing_positions lb in
      let col = pos.pos_cnum - pos.pos_bol + 1 in
      raise
        (Failure
           (Printf.sprintf "Lexing error at %s:%d:%d: %s" pos.pos_fname pos.pos_lnum col msg))
  | e ->
      let pos, _ = Sedlexing.lexing_positions lb in
      Printf.eprintf "Parse error at %s:%d:%d\n" pos.pos_fname pos.pos_lnum
        (pos.pos_cnum - pos.pos_bol);
      raise e
