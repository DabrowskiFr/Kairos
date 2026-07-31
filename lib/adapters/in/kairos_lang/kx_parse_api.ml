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
  import_loc : Kx_loc.loc option;
}

type source = {
  imports : import_decl list;
  type_decls : Kx_core_syntax.enum_decl list;
  function_decls : Kx_core_syntax.pure_function_decl list;
  nodes : Kx_ast.program;
}

type surface_source = Kx_surface_syntax.source

let imported_paths (parsed_source : source) : string list =
  List.map (fun decl -> decl.import_path) parsed_source.imports

type parse_error = {
  loc : Kx_loc.loc option;
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
    let module I = Kx_parser.MenhirInterpreter in
    let push_lexeme s =
      if s <> "" then
        last_two :=
          match !last_two with [] -> [ s ] | [ a ] -> [ a; s ] | [ _; b ] -> [ b; s ] | _ -> [ s ]
    in
    let supplier () =
      let tok = Kx_lexer.token lb in
      push_lexeme (Kx_lexer.last_lexeme ());
      let startp, endp = Sedlexing.lexing_positions lb in
      (tok, startp, endp)
    in
    let handle_error checkpoint_input _checkpoint_error =
      let pos, _ = Sedlexing.lexing_positions lb in
      let col = pos.pos_cnum - pos.pos_bol + 1 in
      let lexeme =
        let s = Kx_lexer.last_lexeme () in
        if s = "" then "<eof>" else s
      in
      let expected =
        let tokens =
          List.filter
            (fun (_name, tok) -> I.acceptable checkpoint_input tok pos)
            Kx_lexer.expected_tokens
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
      Kx_frontend_error.parse
        (Printf.sprintf "Parse error at %s:%d:%d near '%s'%s.%s" pos.pos_fname
           pos.pos_lnum col lexeme context expected)
    in
    let checkpoint = Kx_parser.Incremental.source_file start_pos in
    let surface_source = I.loop_handle_undo (fun v -> v) handle_error supplier checkpoint in
    (surface_source, make_parse_info filename file_hash)
  with
  | Kx_lexer.Lexing_error msg ->
      let pos, _ = Sedlexing.lexing_positions lb in
      let col = pos.pos_cnum - pos.pos_bol + 1 in
      Kx_frontend_error.parse
        (Printf.sprintf "Lexing error at %s:%d:%d: %s" pos.pos_fname
           pos.pos_lnum col msg)
  | e ->
      raise e

let read_import_text ~(importer : string) (path : string) : string =
  try
    let ic = open_in_bin path in
    let len = in_channel_length ic in
    let text = really_input_string ic len in
    close_in ic;
    text
  with exn ->
    Kx_frontend_error.elaboration
      (Printf.sprintf "cannot import spec file '%s' from '%s': %s" path
         importer (Printexc.to_string exn))

let canonical_import_path ~(importer : string) (path : string) : string =
  let candidate =
    if Filename.is_relative path then
      Filename.concat (Filename.dirname importer) path
    else path
  in
  try Unix.realpath candidate
  with Unix.Unix_error (error, _, _) ->
    Kx_frontend_error.elaboration
      (Printf.sprintf "cannot import spec file '%s' from '%s': %s" path
         importer (Unix.error_message error))

let spec_decl_name = function
  | Kx_surface_syntax.SSpecDefDecl decl -> Some decl.spec_def_name
  | _ -> None

let validate_spec_library ~(path : string)
    (source : Kx_surface_syntax.source) : unit =
  if source.nodes <> [] then
    Kx_frontend_error.elaboration
      (Printf.sprintf
         "imported spec file '%s' must not declare nodes" path);
  List.iter
    (fun decl ->
      match spec_decl_name decl with
      | Some _ -> ()
      | None ->
          Kx_frontend_error.elaboration
            (Printf.sprintf
               "imported spec file '%s' may contain only spec definitions"
               path))
    source.frontend_decls

let resolve_spec_imports ~(filename : string)
    (root : Kx_surface_syntax.source) : Kx_surface_syntax.source =
  if root.imports = [] then root
  else
    let root_path =
      try Unix.realpath filename
      with Unix.Unix_error _ ->
        if Filename.is_relative filename then
          Filename.concat (Sys.getcwd ()) filename
        else filename
    in
    let loaded = Hashtbl.create 16 in
    let rec load_library ~(stack : string list) ~(importer : string)
        ((path, _) : Kx_surface_syntax.import_decl) =
      let resolved = canonical_import_path ~importer path in
      if List.mem resolved stack then (
        let cycle = List.rev (resolved :: stack) |> String.concat " -> " in
        Kx_frontend_error.elaboration
          (Printf.sprintf "cyclic spec import: %s" cycle))
      else if Hashtbl.mem loaded resolved then []
      else (
        Hashtbl.add loaded resolved ();
        let text = read_import_text ~importer resolved in
        let source, _ =
          parse_surface_text_with_info ~filename:resolved ~text
        in
        validate_spec_library ~path:resolved source;
        let imported =
          List.concat_map
            (load_library ~stack:(resolved :: stack) ~importer:resolved)
            source.imports
        in
        imported @ source.frontend_decls)
    in
    let imported_decls =
      List.concat_map
        (load_library ~stack:[ root_path ] ~importer:root_path)
        root.imports
    in
    { root with frontend_decls = imported_decls @ root.frontend_decls }

let parse_source_text_with_info ~(filename : string) ~(text : string) : source * parse_info =
  let surface_source, info = parse_surface_text_with_info ~filename ~text in
  let surface_source = resolve_spec_imports ~filename surface_source in
  let elaborated_source = Kx_elaborate.elaborate_source surface_source in
  let imports =
    List.map
      (fun (import_path, import_loc) -> { import_path; import_loc })
      elaborated_source.imports
  in
  let parsed_source =
    {
      imports;
      type_decls = elaborated_source.type_decls;
      function_decls = elaborated_source.function_decls;
      nodes = elaborated_source.nodes;
    }
  in
  (parsed_source, info)

let import_decl_to_yojson (decl : import_decl) : Yojson.Safe.t =
  let loc_json =
    match decl.import_loc with
    | None -> `Null
    | Some loc -> Kx_loc.loc_to_yojson loc
  in
  `Assoc
    [
      ("import_path", `String decl.import_path);
      ("import_loc", loc_json);
    ]

let source_to_yojson (source : source) : Yojson.Safe.t =
  `Assoc
    [
      ("imports", `List (List.map import_decl_to_yojson source.imports));
      ("type_decls", `List (List.map Kx_core_syntax.enum_decl_to_yojson source.type_decls));
      ( "function_decls",
        `List (List.map Kx_core_syntax.pure_function_decl_to_yojson source.function_decls) );
      ("nodes", Kx_ast.program_to_yojson source.nodes);
    ]

let json_to_string json = Yojson.Safe.pretty_to_string json ^ "\n"

let surface_source_to_json (source : surface_source) : string =
  json_to_string (Kx_surface_syntax.source_to_yojson source)

let source_to_json (source : source) : string =
  json_to_string (source_to_yojson source)
