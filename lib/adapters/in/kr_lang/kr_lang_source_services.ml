type source_diagnostic = {
  line : int;
  column : int;
  line_end : int;
  column_end : int;
  severity : int;
  source : string;
  message : string;
}

type semantic_symbols = {
  all : string list;
  nodes : string list;
  states : string list;
  variables : string list;
}

let source_diagnostic ~loc ~severity ~source ~message =
  let line, column, line_end, column_end =
    match loc with
    | Some (loc : Kr_lang_shared.Kr_lang_shared_syntax.loc) ->
        (max 0 (loc.line - 1), loc.col, max 0 (loc.line_end - 1), loc.col_end)
    | None -> (0, 0, 0, 0)
  in
  { line; column; line_end; column_end; severity; source; message }

(* [frontend_error_source] implements the internal frontend error source operation. It returns the operation result. *)
let frontend_error_source = function
  | Kr_lang_shared.Kr_lang_shared_error.Parse -> "kairos-parse"
  | Kr_lang_shared.Kr_lang_shared_error.Elaboration -> "kairos-elaboration"
  | Kr_lang_shared.Kr_lang_shared_error.Type -> "kairos-type"
  | Kr_lang_shared.Kr_lang_shared_error.Well_formedness -> "kairos-well-formedness"
  | Kr_lang_shared.Kr_lang_shared_error.Internal -> "kairos-internal"

let diagnostics ~filename ~text =
  try
    let _source, info =
      Kr_lang_parse.Kr_lang_parse_parser.elaborate_source_text_with_info ~filename ~text
    in
    let diagnostics = ref [] in
    List.iter
      (fun warning ->
        diagnostics :=
          source_diagnostic ~loc:None ~severity:2 ~source:"kairos-parse"
            ~message:warning
          :: !diagnostics)
      info.Kr_lang_parse.Kr_lang_parse_parser.warnings;
    List.rev !diagnostics
  with
  | Kr_lang_shared.Kr_lang_shared_error.Error error ->
      [
        source_diagnostic ~loc:error.loc ~severity:1
          ~source:(frontend_error_source error.kind)
          ~message:error.message;
      ]
  | exn ->
      [
        source_diagnostic ~loc:None ~severity:1 ~source:"kairos-internal"
          ~message:(Printexc.to_string exn);
      ]

let semantic_symbols ~filename ~text =
  try
    let source = Kr_lang_parse.Kr_lang_parse_parser.elaborate_source_text ~filename ~text in
    let all = Hashtbl.create 256 in
    let nodes = Hashtbl.create 64 in
    let states = Hashtbl.create 128 in
    let variables = Hashtbl.create 256 in
    let add table value =
      if value <> "" then Hashtbl.replace table value ()
    in
    List.iter
      (fun (node : Kr_lang_core.Kr_lang_core_ast.node) ->
        let semantics = node.semantics in
        add nodes semantics.sem_nname;
        add all semantics.sem_nname;
        List.iter
          (fun state ->
            add states state;
            add all state)
          semantics.sem_states;
        List.iter
          (fun variable ->
            add variables variable.Kr_lang_core.Kr_lang_core_syntax.vname;
            add all variable.Kr_lang_core.Kr_lang_core_syntax.vname)
          (semantics.sem_inputs @ semantics.sem_outputs
         @ semantics.sem_locals))
      source.nodes;
    let keys table =
      Hashtbl.to_seq_keys table |> List.of_seq
      |> List.sort_uniq String.compare
    in
    Some
      {
        all = keys all;
        nodes = keys nodes;
        states = keys states;
        variables = keys variables;
      }
  with _ -> None

(* [frontend_error (error : Kr_lang_shared.Kr_lang_shared_error.t)] implements the internal frontend error operation. It returns the operation result. *)
let frontend_error (error : Kr_lang_shared.Kr_lang_shared_error.t) =
  let diagnostic = { Kr_lang_frontend.loc = error.loc; message = error.message } in
  match error.kind with
  | Kr_lang_shared.Kr_lang_shared_error.Parse -> Kr_lang_frontend.Parse_error diagnostic
  | Kr_lang_shared.Kr_lang_shared_error.Elaboration ->
      Kr_lang_frontend.Elaboration_error diagnostic
  | Kr_lang_shared.Kr_lang_shared_error.Type -> Kr_lang_frontend.Type_error diagnostic
  | Kr_lang_shared.Kr_lang_shared_error.Well_formedness ->
      Kr_lang_frontend.Well_formedness_error diagnostic
  | Kr_lang_shared.Kr_lang_shared_error.Internal -> Kr_lang_frontend.Internal_error error.message

(* [read_text input_file] implements the internal read text operation. It returns the operation result. *)
let read_text input_file =
  try
    Ok (In_channel.with_open_bin input_file In_channel.input_all)
  with exn -> Error (Kr_lang_frontend.Io_error (Printexc.to_string exn))

(* [dump parse render ~input_file] implements the internal dump operation. It returns the operation result. *)
let dump parse render ~input_file =
  match read_text input_file with
  | Error _ as error -> error
  | Ok text -> (
      try Ok (render (parse ~filename:input_file ~text)) with
      | Kr_lang_shared.Kr_lang_shared_error.Error error -> Error (frontend_error error)
      | exn ->
          Error (Kr_lang_frontend.Internal_error (Printexc.to_string exn)))

let surface_dump ~input_file =
  dump Kr_lang_parse.Kr_lang_parse_parser.parse_surface_text
    Kr_lang_parse.Kr_lang_parse_parser.surface_source_to_json ~input_file

let elaborated_dump ~input_file =
  dump Kr_lang_parse.Kr_lang_parse_parser.elaborate_source_text Kr_lang_parse.Kr_lang_parse_parser.source_to_json
    ~input_file
