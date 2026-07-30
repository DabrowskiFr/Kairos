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

type error =
  | Parse_error of string
  | Elaboration_error of string
  | Type_error of string
  | Well_formedness_error of string
  | Io_error of string
  | Internal_error of string

type parse_error = { loc : Loc.loc option; message : string }

type parse_info = {
  source_path : string option;
  text_hash : string option;
  parse_errors : parse_error list;
  warnings : string list;
}

type input = {
  imports : string list;
  parse_info : parse_info;
  verification_model : Verification_model.program_model;
}

let parse_info_of_frontend (info : Kx_parse_api.parse_info) : parse_info =
  {
    source_path = info.source_path;
    text_hash = info.text_hash;
    parse_errors =
      List.map
        (fun (e : Kx_parse_api.parse_error) ->
          ({
             loc =
               Option.map
                 (fun (l : Kx_loc.loc) ->
                   { Loc.line = l.line; col = l.col; line_end = l.line_end; col_end = l.col_end })
                 e.loc;
             message = e.message;
           }
            : parse_error))
        info.parse_errors;
    warnings = info.warnings;
  }

let structured_frontend_error (err : Kx_frontend_error.t) : error =
  match err.kind with
  | Kx_frontend_error.Parse -> Parse_error err.message
  | Kx_frontend_error.Elaboration -> Elaboration_error err.message
  | Kx_frontend_error.Type -> Type_error err.message
  | Kx_frontend_error.Well_formedness ->
      Well_formedness_error err.message
  | Kx_frontend_error.Internal -> Internal_error err.message

let read_all_text (path : string) : (string, error) result =
  try
    let ic = open_in_bin path in
    let len = in_channel_length ic in
    let s = really_input_string ic len in
    close_in ic;
    Ok s
  with exn -> Error (Io_error (Printexc.to_string exn))

let normalize_path path =
  let absolute =
    if Filename.is_relative path then Filename.concat (Sys.getcwd ()) path
    else path
  in
  let parts = String.split_on_char '/' absolute in
  let normalized =
    List.fold_left
      (fun acc -> function
        | "" | "." -> acc
        | ".." -> (match acc with [] -> [] | _ :: rest -> rest)
        | part -> part :: acc)
      [] parts
    |> List.rev
  in
  "/" ^ String.concat "/" normalized

let resolve_import_path ~owner import_path =
  let candidate =
    if Filename.is_relative import_path then
      Filename.concat (Filename.dirname owner) import_path
    else import_path
  in
  normalize_path candidate

let load_surface_with_imports ~(input_file : string) :
    ( Kx_surface_syntax.source * Kx_parse_api.parse_info * string list,
      error )
    result =
  let visited = Hashtbl.create 16 in
  let resolved_imports = ref [] in
  let empty_source () : Kx_surface_syntax.source =
    { imports = []; frontend_decls = []; nodes = [] }
  in
  let merge (left : Kx_surface_syntax.source)
      (right : Kx_surface_syntax.source) : Kx_surface_syntax.source =
    {
      imports = [];
      frontend_decls = left.frontend_decls @ right.frontend_decls;
      nodes = left.nodes @ right.nodes;
    }
  in
  let rec load ~root ~stack path =
    let path = normalize_path path in
    if List.mem path stack then
      Error
        (Elaboration_error
           (Printf.sprintf "cyclic import: %s"
              (String.concat " -> " (List.rev (path :: stack)))))
    else if Hashtbl.mem visited path then
      Ok (empty_source (), None)
    else
      match read_all_text path with
      | Error _ as error -> error
      | Ok text -> (
          try
            let surface, info =
              Kx_parse_api.parse_surface_text_with_info ~filename:path ~text
            in
            Hashtbl.add visited path ();
            let rec load_imports acc = function
              | [] -> Ok acc
              | (import_path, _) :: rest ->
                  let imported =
                    resolve_import_path ~owner:path import_path
                  in
                  resolved_imports := !resolved_imports @ [ imported ];
                  (match load ~root:false ~stack:(path :: stack) imported with
                  | Error _ as error -> error
                  | Ok (source, _) ->
                      load_imports (merge acc source) rest)
            in
            match load_imports (empty_source ()) surface.imports with
            | Error _ as error -> error
            | Ok imported ->
                let current = { surface with imports = [] } in
                Ok (merge imported current, if root then Some info else None)
          with
          | Kx_frontend_error.Error err ->
              Error (structured_frontend_error err)
          | exn -> Error (Internal_error (Printexc.to_string exn)))
  in
  match load ~root:true ~stack:[] input_file with
  | Error _ as error -> error
  | Ok (source, Some info) ->
      Ok (source, info, !resolved_imports)
  | Ok (_, None) ->
      Error
        (Internal_error
           "root source lost its parse diagnostics during import resolution")

let parse_input ~(input_file : string) : (input, error) result =
  match load_surface_with_imports ~input_file with
  | Error _ as err -> err
  | Ok (surface_source, parse_info_kx, resolved_imports) -> (
      try
        let source_kx = Kx_elaborate.elaborate_source surface_source in
        let parse_info = parse_info_of_frontend parse_info_kx in
        let parsed_model =
          Kairos_to_model.program ~type_decls:source_kx.type_decls
            ~function_decls:source_kx.function_decls source_kx.nodes
        in
        let instance_decls =
          List.map
            (fun (node : Kx_ast.node) ->
              let semantics = Kx_ast.semantics_of_node node in
              (semantics.sem_nname, semantics.sem_instances))
            source_kx.nodes
        in
        let verification_model =
          Kx_hierarchy_inline.flatten_program ~instance_decls parsed_model
        in
        Ok
          {
            imports = resolved_imports;
            parse_info;
            verification_model;
          }
      with
      | Kx_frontend_error.Error err -> Error (structured_frontend_error err)
      | exn -> Error (Internal_error (Printexc.to_string exn)))
