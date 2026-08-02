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

type source = {
  type_decls : Core.Syntax.enum_decl list;
  function_decls : Core.Syntax.pure_function_decl list;
  nodes : Core.Ast.program;
}

type surface_source = Surface.Ast.source

type parse_error = {
  loc : Shared.Syntax.loc option;
  message : string;
}

type parse_info = {
  source_path : string option;
  text_hash : string option;
  parse_errors : parse_error list;
  warnings : string list;
}

let make_parse_info filename file_hash =
  {
    source_path = Some filename;
    text_hash = Some file_hash;
    parse_errors = [];
    warnings = [];
  }

let parse_surface_text_with_info ~(filename : string) ~(text : string) :
    surface_source * parse_info =
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
      Shared.Error.parse
        (Printf.sprintf "Parse error at %s:%d:%d near '%s'%s.%s" pos.pos_fname
           pos.pos_lnum col lexeme context expected)
    in
    let checkpoint = Parser.Incremental.source_file start_pos in
    let surface_source = I.loop_handle_undo (fun v -> v) handle_error supplier checkpoint in
    (surface_source, make_parse_info filename file_hash)
  with
  | Lexer.Lexing_error msg ->
      let pos, _ = Sedlexing.lexing_positions lb in
      let col = pos.pos_cnum - pos.pos_bol + 1 in
      Shared.Error.parse
        (Printf.sprintf "Lexing error at %s:%d:%d: %s" pos.pos_fname
           pos.pos_lnum col msg)
  | e ->
      raise e

let parse_source_text_with_info ~(filename : string) ~(text : string) : source * parse_info =
  let surface_source, info = parse_surface_text_with_info ~filename ~text in
  let elaborated_source = Elaborate.Api.elaborate_source surface_source in
  let parsed_source =
    {
      type_decls = elaborated_source.type_decls;
      function_decls = elaborated_source.function_decls;
      nodes = elaborated_source.nodes;
    }
  in
  (parsed_source, info)

let source_to_yojson (source : source) : Yojson.Safe.t =
  `Assoc
    [
      ("type_decls", `List (List.map Core.Syntax.enum_decl_to_yojson source.type_decls));
      ( "function_decls",
        `List (List.map Core.Syntax.pure_function_decl_to_yojson source.function_decls) );
      ("nodes", Core.Ast.program_to_yojson source.nodes);
    ]

let json_to_string json = Yojson.Safe.pretty_to_string json ^ "\n"

let surface_source_to_json (source : surface_source) : string =
  json_to_string (Surface.Ast.source_to_yojson source)

let source_to_json (source : source) : string =
  json_to_string (source_to_yojson source)
