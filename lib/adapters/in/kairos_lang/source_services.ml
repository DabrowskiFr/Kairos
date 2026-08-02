type source_diagnostic = {
  line : int;
  column : int;
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

let parse_line_column message =
  let pattern = Str.regexp ".*:\\([0-9]+\\):\\([0-9]+\\)" in
  if Str.string_match pattern message 0 then
    Some
      ( int_of_string (Str.matched_group 1 message),
        int_of_string (Str.matched_group 2 message) )
  else None

let source_diagnostic ~severity ~source ~message =
  let line, column =
    match parse_line_column message with
    | Some (line, column) -> (max 0 (line - 1), max 0 (column - 1))
    | None -> (0, 0)
  in
  { line; column; severity; source; message }

let frontend_error_source = function
  | Shared.Error.Parse -> "kairos-parse"
  | Shared.Error.Elaboration -> "kairos-elaboration"
  | Shared.Error.Type -> "kairos-type"
  | Shared.Error.Well_formedness -> "kairos-well-formedness"
  | Shared.Error.Internal -> "kairos-internal"

let diagnostics ~filename ~text =
  try
    let _source, info =
      Parse.Api.parse_source_text_with_info ~filename ~text
    in
    let diagnostics = ref [] in
    List.iter
      (fun error ->
        diagnostics :=
          source_diagnostic ~severity:1 ~source:"kairos-parse"
            ~message:error.Parse.Api.message
          :: !diagnostics)
      info.Parse.Api.parse_errors;
    List.iter
      (fun warning ->
        diagnostics :=
          source_diagnostic ~severity:2 ~source:"kairos-parse"
            ~message:warning
          :: !diagnostics)
      info.Parse.Api.warnings;
    List.rev !diagnostics
  with
  | Shared.Error.Error error ->
      [
        source_diagnostic ~severity:1
          ~source:(frontend_error_source error.kind)
          ~message:error.message;
      ]
  | exn ->
      [
        source_diagnostic ~severity:1 ~source:"kairos-internal"
          ~message:(Printexc.to_string exn);
      ]

let semantic_symbols ~filename ~text =
  try
    let source, _info =
      Parse.Api.parse_source_text_with_info ~filename ~text
    in
    let all = Hashtbl.create 256 in
    let nodes = Hashtbl.create 64 in
    let states = Hashtbl.create 128 in
    let variables = Hashtbl.create 256 in
    let add table value =
      if value <> "" then Hashtbl.replace table value ()
    in
    List.iter
      (fun (node : Core.Ast.node) ->
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
            add variables variable.Core.Syntax.vname;
            add all variable.Core.Syntax.vname)
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

let frontend_error (error : Shared.Error.t) =
  match error.kind with
  | Shared.Error.Parse -> Frontend.Parse_error error.message
  | Shared.Error.Elaboration ->
      Frontend.Elaboration_error error.message
  | Shared.Error.Type -> Frontend.Type_error error.message
  | Shared.Error.Well_formedness ->
      Frontend.Well_formedness_error error.message
  | Shared.Error.Internal -> Frontend.Internal_error error.message

let read_text input_file =
  try
    Ok (In_channel.with_open_bin input_file In_channel.input_all)
  with exn -> Error (Frontend.Io_error (Printexc.to_string exn))

let dump parse render ~input_file =
  match read_text input_file with
  | Error _ as error -> error
  | Ok text -> (
      try Ok (render (parse ~filename:input_file ~text |> fst)) with
      | Shared.Error.Error error -> Error (frontend_error error)
      | exn ->
          Error (Frontend.Internal_error (Printexc.to_string exn)))

let surface_dump ~input_file =
  dump Parse.Api.parse_surface_text_with_info
    Parse.Api.surface_source_to_json ~input_file

let elaborated_dump ~input_file =
  dump Parse.Api.parse_source_text_with_info Parse.Api.source_to_json
    ~input_file
