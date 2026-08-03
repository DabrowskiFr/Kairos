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

type source = Elaborate.Api.source

type surface_source = Surface.Ast.source

type parse_info = {
  source_path : string option;
  text_hash : string option;
  warnings : string list;
}

let make_parse_info filename file_hash =
  {
    source_path = Some filename;
    text_hash = Some file_hash;
    warnings = [];
  }

let quote_lexeme lexeme = Printf.sprintf "%S" lexeme

type error_lexeme = End_of_file | Lexeme of string

let error_lexeme = function "" -> End_of_file | lexeme -> Lexeme lexeme

let display_error_lexeme = function
  | End_of_file -> "end of file"
  | Lexeme lexeme -> quote_lexeme lexeme

let max_expected_tokens = 8

let parse_surface_text_with_info ~(filename : string) ~(text : string) :
    surface_source * parse_info =
  let file_hash = Digest.to_hex (Digest.string text) in
  let lb = Sedlexing.Utf8.from_string text in
  Sedlexing.set_filename lb filename;
  try
    let previous_lexeme = ref None in
    let current_lexeme = ref None in
    let start_pos = { Lexing.pos_fname = filename; pos_lnum = 1; pos_bol = 0; pos_cnum = 0 } in
    let module I = Parser.MenhirInterpreter in
    let push_lexeme lexeme =
      previous_lexeme := !current_lexeme;
      current_lexeme :=
        (match error_lexeme lexeme with
        | End_of_file -> None
        | Lexeme lexeme -> Some lexeme)
    in
    let supplier () =
      let tok = Lexer.token lb in
      push_lexeme (Lexer.last_lexeme ());
      let startp, endp = Sedlexing.lexing_positions lb in
      (tok, startp, endp)
    in
    let handle_error checkpoint_before_token _checkpoint_at_error =
      let start_pos, end_pos = Sedlexing.lexing_positions lb in
      let loc = Shared.Syntax.loc_of_positions start_pos end_pos in
      let lexeme = error_lexeme (Lexer.last_lexeme ()) in
      let expected_message =
        (* Use the checkpoint before the failing token so that [acceptable]
           reports tokens valid at the error location. *)
        let rec accepted_names remaining names = function
          | _ when remaining = 0 -> List.rev names
          | [] -> List.rev names
          | (name, token) :: rest ->
              if I.acceptable checkpoint_before_token token start_pos then
                accepted_names (remaining - 1) (name :: names) rest
              else accepted_names remaining names rest
        in
        match
          accepted_names max_expected_tokens [] Lexer.expected_tokens
        with
        | [] -> ""
        | tokens -> "; expected " ^ String.concat ", " tokens
      in
      let context =
        match !previous_lexeme with
        | Some previous ->
            Printf.sprintf " after %s" (quote_lexeme previous)
        | None -> ""
      in
      Shared.Error.parse ~loc
        (Printf.sprintf "Unexpected token %s%s%s"
           (display_error_lexeme lexeme) context expected_message)
    in
    let checkpoint = Parser.Incremental.source_file start_pos in
    let surface_source = I.loop_handle_undo (fun v -> v) handle_error supplier checkpoint in
    (surface_source, make_parse_info filename file_hash)
  with
  | Lexer.Lexing_error (loc, msg) ->
      Shared.Error.parse ~loc (Printf.sprintf "Lexing error: %s" msg)

let elaborate_source_text_with_info ~(filename : string) ~(text : string) :
    source * parse_info =
  let surface_source, info = parse_surface_text_with_info ~filename ~text in
  let source = Elaborate.Api.elaborate_source surface_source in
  (source, info)

let elaborate_source_text ~filename ~text =
  elaborate_source_text_with_info ~filename ~text |> fst

let parse_surface_text ~filename ~text =
  parse_surface_text_with_info ~filename ~text |> fst

let source_to_yojson (source : source) : Yojson.Safe.t =
  `Assoc
    [
      ("type_decls", `List (List.map Core.Syntax.enum_decl_to_yojson source.type_decls));
      ( "function_decls",
        `List (List.map Core.Syntax.pure_function_decl_to_yojson source.function_decls) );
      ("nodes", Core.Ast.program_to_yojson source.nodes);
    ]

let pretty_json_to_string json = Yojson.Safe.pretty_to_string json ^ "\n"

let surface_source_to_json (source : surface_source) : string =
  pretty_json_to_string (Surface.Ast.source_to_yojson source)

let source_to_json (source : source) : string =
  pretty_json_to_string (source_to_yojson source)
