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
  | Kx_frontend_error.Parse -> "kairos-parse"
  | Kx_frontend_error.Elaboration -> "kairos-elaboration"
  | Kx_frontend_error.Type -> "kairos-type"
  | Kx_frontend_error.Well_formedness -> "kairos-well-formedness"
  | Kx_frontend_error.Internal -> "kairos-internal"

let diagnostics ~filename ~text =
  try
    let _source, info =
      Kx_parse_api.parse_source_text_with_info ~filename ~text
    in
    let diagnostics = ref [] in
    List.iter
      (fun error ->
        diagnostics :=
          source_diagnostic ~severity:1 ~source:"kairos-parse"
            ~message:error.Kx_parse_api.message
          :: !diagnostics)
      info.Kx_parse_api.parse_errors;
    List.iter
      (fun warning ->
        diagnostics :=
          source_diagnostic ~severity:2 ~source:"kairos-parse"
            ~message:warning
          :: !diagnostics)
      info.Kx_parse_api.warnings;
    List.rev !diagnostics
  with
  | Kx_frontend_error.Error error ->
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
      Kx_parse_api.parse_source_text_with_info ~filename ~text
    in
    let all = Hashtbl.create 256 in
    let nodes = Hashtbl.create 64 in
    let states = Hashtbl.create 128 in
    let variables = Hashtbl.create 256 in
    let add table value =
      if value <> "" then Hashtbl.replace table value ()
    in
    List.iter
      (fun (node : Kx_ast.node) ->
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
            add variables variable.Kx_core_syntax.vname;
            add all variable.Kx_core_syntax.vname)
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

let frontend_error (error : Kx_frontend_error.t) =
  match error.kind with
  | Kx_frontend_error.Parse -> Kairos_frontend.Parse_error error.message
  | Kx_frontend_error.Elaboration ->
      Kairos_frontend.Elaboration_error error.message
  | Kx_frontend_error.Type -> Kairos_frontend.Type_error error.message
  | Kx_frontend_error.Well_formedness ->
      Kairos_frontend.Well_formedness_error error.message
  | Kx_frontend_error.Internal -> Kairos_frontend.Internal_error error.message

let read_text input_file =
  try
    let channel = open_in_bin input_file in
    Fun.protect ~finally:(fun () -> close_in_noerr channel) (fun () ->
        let length = in_channel_length channel in
        Ok (really_input_string channel length))
  with exn -> Error (Kairos_frontend.Io_error (Printexc.to_string exn))

let dump parse render ~input_file =
  match read_text input_file with
  | Error _ as error -> error
  | Ok text -> (
      try Ok (render (parse ~filename:input_file ~text |> fst)) with
      | Kx_frontend_error.Error error -> Error (frontend_error error)
      | exn ->
          Error (Kairos_frontend.Internal_error (Printexc.to_string exn)))

let surface_dump ~input_file =
  dump Kx_parse_api.parse_surface_text_with_info
    Kx_parse_api.surface_source_to_json ~input_file

let elaborated_dump ~input_file =
  dump Kx_parse_api.parse_source_text_with_info Kx_parse_api.source_to_json
    ~input_file
