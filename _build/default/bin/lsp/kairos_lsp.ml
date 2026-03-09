open Yojson.Safe

let env_bool name =
  match Sys.getenv_opt name with
  | Some ("1" | "true" | "TRUE" | "yes" | "YES" | "on" | "ON") -> true
  | _ -> false

let trace_enabled = env_bool "KAIROS_LSP_TRACE"
let trace_file = Option.value (Sys.getenv_opt "KAIROS_LSP_TRACE_FILE") ~default:"/tmp/kairos-lsp-trace.log"

let trace_line (who : string) (msg : string) : unit =
  if trace_enabled then (
    let oc = open_out_gen [ Open_creat; Open_text; Open_append ] 0o644 trace_file in
    let tm = Unix.localtime (Unix.gettimeofday ()) in
    Printf.fprintf oc "%04d-%02d-%02d %02d:%02d:%02d [%s] %s\n"
      (tm.tm_year + 1900) (tm.tm_mon + 1) tm.tm_mday tm.tm_hour tm.tm_min tm.tm_sec who msg;
    close_out_noerr oc)

let send_raw (oc : out_channel) (body : string) : unit =
  output_string oc (Printf.sprintf "Content-Length: %d\r\n\r\n%s" (String.length body) body);
  flush oc

let send_json oc (j : Yojson.Safe.t) =
  let s = Yojson.Safe.to_string j in
  trace_line "lsp-server -> client" s;
  send_raw oc s

let send_result (oc : out_channel) ~(id_json : Yojson.Safe.t) ~(result_json : Yojson.Safe.t) : unit =
  send_json oc (`Assoc [ ("jsonrpc", `String "2.0"); ("id", id_json); ("result", result_json) ])

let send_error (oc : out_channel) ~(id_json : Yojson.Safe.t option) ~(code : int) ~(message : string) : unit =
  send_json oc
    (`Assoc
      [ ("jsonrpc", `String "2.0");
        ("id", Option.value id_json ~default:`Null);
        ("error", `Assoc [ ("code", `Int code); ("message", `String message) ]) ])

let send_notification (oc : out_channel) ~(method_name : string) ~(params_json : Yojson.Safe.t) : unit =
  send_json oc
    (`Assoc [ ("jsonrpc", `String "2.0"); ("method", `String method_name); ("params", params_json) ])

let send_request (oc : out_channel) ~(id_json : Yojson.Safe.t) ~(method_name : string)
    ~(params_json : Yojson.Safe.t) : unit =
  send_json oc
    (`Assoc
      [
        ("jsonrpc", `String "2.0");
        ("id", id_json);
        ("method", `String method_name);
        ("params", params_json);
      ])

let send_publish_diagnostics (oc : out_channel) ~(uri : string) ~(diagnostics : Yojson.Safe.t list)
    : unit =
  send_notification oc ~method_name:"textDocument/publishDiagnostics"
    ~params_json:(`Assoc [ ("uri", `String uri); ("diagnostics", `List diagnostics) ])

let path_of_uri (uri : string) : string option =
  let prefix = "file://" in
  if String.length uri >= String.length prefix
     && String.sub uri 0 (String.length prefix) = prefix
  then Some (String.sub uri (String.length prefix) (String.length uri - String.length prefix))
  else if Filename.is_relative uri then None
  else Some uri

let diagnostic_to_json (d : Lsp_services.diagnostic) : Yojson.Safe.t =
  `Assoc
    [
      ( "range",
        `Assoc
          [
            ("start", `Assoc [ ("line", `Int d.line); ("character", `Int d.col) ]);
            ("end", `Assoc [ ("line", `Int d.line); ("character", `Int (d.col + 1)) ]);
          ] );
      ("severity", `Int d.severity);
      ("source", `String d.source);
      ("message", `String d.message);
    ]

let parse_diagnostics_for_text ~(uri : string) ~(text : string) : Yojson.Safe.t list =
  Lsp_services.diagnostics_for_text ~uri ~text |> List.map diagnostic_to_json

let range_json ~line ~c1 ~c2 : Yojson.Safe.t =
  `Assoc
    [
      ("start", `Assoc [ ("line", `Int line); ("character", `Int c1) ]);
      ("end", `Assoc [ ("line", `Int line); ("character", `Int c2) ]);
    ]

let find_identifier_occurrences = Lsp_services.identifier_occurrences
type semantic_symbols = Lsp_services.semantic_symbols
let semantic_symbols_of_program = Lsp_services.semantic_symbols_of_program
let parse_program_from_text = Lsp_services.parse_program_from_text
let first_definition_position = Lsp_services.first_definition_position
let position_from_params = Lsp_app.position_from_params
let map_outputs = Lsp_app.map_outputs
let map_automata = Lsp_app.map_automata
let map_obc = Lsp_app.map_obc
let map_why = Lsp_app.map_why
let map_oblig = Lsp_app.map_oblig
let get_param_string = Lsp_app.get_param_string
let get_param_bool = Lsp_app.get_param_bool
let get_param_int = Lsp_app.get_param_int
let get_param_obj = Lsp_app.get_param_obj
let get_param_list = Lsp_app.get_param_list
let get_text_document_uri = Lsp_app.get_text_document_uri
let get_did_open_text = Lsp_app.get_did_open_text
let get_did_change_text = Lsp_app.get_did_change_text
let client_supports_work_done_progress = Lsp_app.client_supports_work_done_progress

let get_engine (params : Yojson.Safe.t) : Engine_service.engine =
  match get_param_string params "engine" with
  | Some s -> Option.value (Engine_service.engine_of_string s) ~default:Engine_service.V2
  | None -> Engine_service.V2

let symbol_info ~(uri : string) ~(name : string) ~(line : int) ~(character : int) : Yojson.Safe.t =
  `Assoc
    [
      ("name", `String name);
      ("kind", `Int 12);
      ( "location",
        `Assoc
          [
            ("uri", `String uri);
            ( "range",
              `Assoc
                [
                  ("start", `Assoc [ ("line", `Int line); ("character", `Int character) ]);
                  ("end", `Assoc [ ("line", `Int line); ("character", `Int (character + 1)) ]);
                ] );
          ] );
    ]

type outline_sections = Lsp_services.outline_sections
let outline_sections_of_text = Lsp_services.outline_sections_of_text

let yojson_of_outline_sections = Lsp_services.yojson_of_outline_sections

let goals_tree_json_of_nodes = Lsp_services.yojson_of_goals_tree

let send_work_done_begin (oc : out_channel) ~(token : string) ~(title : string) ~(message : string) : unit =
  send_notification oc ~method_name:"$/progress"
    ~params_json:
      (`Assoc
        [
          ("token", `String token);
          ( "value",
            `Assoc
              [ ("kind", `String "begin"); ("title", `String title); ("message", `String message) ] );
        ])

let send_work_done_report (oc : out_channel) ~(token : string) ~(message : string) : unit =
  send_notification oc ~method_name:"$/progress"
    ~params_json:
      (`Assoc
        [
          ("token", `String token);
          ("value", `Assoc [ ("kind", `String "report"); ("message", `String message) ]);
        ])

let send_work_done_end (oc : out_channel) ~(token : string) ~(message : string) : unit =
  send_notification oc ~method_name:"$/progress"
    ~params_json:
      (`Assoc
        [
          ("token", `String token);
          ("value", `Assoc [ ("kind", `String "end"); ("message", `String message) ]);
        ])

let read_message (ic : in_channel) : string option =
  let rec read_headers acc =
    try
      let line = input_line ic in
      if line = "" || line = "\r" then List.rev acc else read_headers (line :: acc)
    with End_of_file -> List.rev acc
  in
  let headers = read_headers [] in
  if headers = [] then None
  else
    let len_opt =
      List.find_map
        (fun h ->
          try
            if String.lowercase_ascii (String.sub h 0 14) = "content-length" then
              Some (int_of_string (String.trim (String.sub h 15 (String.length h - 15))))
            else None
          with _ -> None)
        headers
    in
    match len_opt with
    | None -> None
    | Some len ->
        let body = really_input_string ic len in
        trace_line "client -> lsp-server" body;
        Some body

let member k = function `Assoc xs -> List.assoc_opt k xs | _ -> None
let as_string = function Some (`String s) -> Some s | _ -> None
let as_assoc = function Some (`Assoc xs) -> Some xs | _ -> None
let as_list = function Some (`List xs) -> Some xs | _ -> None

let method_of_msg j = member "method" j |> as_string
let id_of_msg j = member "id" j
let params_of_msg j = member "params" j
let is_request id_json = Option.is_some id_json
let id_key (id : Yojson.Safe.t) = Yojson.Safe.to_string id

let is_response_message (j : Yojson.Safe.t) : bool =
  match (member "method" j, member "id" j) with
  | None, Some _ -> true
  | _ -> false

let has_valid_jsonrpc (j : Yojson.Safe.t) : bool =
  match member "jsonrpc" j with
  | Some (`String "2.0") -> true
  | _ -> false

let () =
  let docs : (string, string) Hashtbl.t = Hashtbl.create 32 in
  let canceled : (string, unit) Hashtbl.t = Hashtbl.create 64 in
  let next_server_req_id = ref 1 in
  let initialized = ref false in
  let shutdown_requested = ref false in
  let supports_work_done_progress = ref false in
  let running = ref true in
  while !running do
    match read_message stdin with
    | None -> running := false
    | Some body -> (
        let j =
          try Ok (Yojson.Safe.from_string body)
          with _ ->
            send_error stdout ~id_json:None ~code:(-32700) ~message:"Parse error";
            Error ()
        in
        match j with
        | Error () -> ()
        | Ok j when not (has_valid_jsonrpc j) ->
            if is_request (id_of_msg j) then
              send_error stdout ~id_json:(id_of_msg j) ~code:(-32600)
                ~message:"Invalid Request"
        | Ok j when is_response_message j -> ()
        | Ok j ->
        let method_name = method_of_msg j in
        let id_json = id_of_msg j in
        let params = Option.value (params_of_msg j) ~default:(`Assoc []) in
        match method_name with
        | Some "initialize" when !initialized ->
            if is_request id_json then
              send_error stdout ~id_json ~code:(-32600) ~message:"Server already initialized"
        | Some "initialize" ->
            initialized := true;
            supports_work_done_progress := client_supports_work_done_progress params;
            let result =
              `Assoc
                [ ("serverInfo", `Assoc [ ("name", `String "kairos-lsp"); ("version", `String "1.0") ]);
                  ("capabilities",
                   `Assoc
                     [ ("textDocumentSync",
                        `Assoc
                          [
                            ("openClose", `Bool true);
                            ("change", `Int 1);
                            ("save", `Assoc [ ("includeText", `Bool false) ]);
                          ]);
                       ("workDoneProgress", `Bool true);
                       ("hoverProvider", `Bool true);
                       ("definitionProvider", `Bool true);
                       ("referencesProvider", `Bool true);
                       ("documentSymbolProvider", `Bool true);
                       ("completionProvider", `Assoc [ ("triggerCharacters", `List []) ]);
                       ("workspaceSymbolProvider", `Bool true);
                       ("documentFormattingProvider", `Bool true);
                     ]) ]
            in
            Option.iter (fun id -> send_result stdout ~id_json:id ~result_json:result) id_json
        | Some "initialized" when not !initialized -> ()
        | Some "initialized" -> ()
        | Some "$/cancelRequest" -> (
            match params with
            | `Assoc xs -> (
                match List.assoc_opt "id" xs with
                | Some cid -> Hashtbl.replace canceled (id_key cid) ()
                | None -> ())
            | _ -> ())
        | Some "shutdown" when not !initialized ->
            if is_request id_json then
              send_error stdout ~id_json ~code:(-32002)
                ~message:"Server not initialized"
        | Some "shutdown" ->
            shutdown_requested := true;
            Option.iter (fun id -> send_result stdout ~id_json:id ~result_json:`Null) id_json
        | Some "exit" -> if !shutdown_requested then exit 0 else exit 1
        | _ when not !initialized ->
            if is_request id_json then
              send_error stdout ~id_json ~code:(-32002)
                ~message:"Server not initialized"
        | _ when !shutdown_requested ->
            if is_request id_json then
              send_error stdout ~id_json ~code:(-32600)
                ~message:"Invalid request: server is shut down"
        | Some "textDocument/didOpen" -> (
            let uri = get_text_document_uri params in
            let text = get_did_open_text params in
            match (uri, text) with
            | Some u, Some t ->
                Hashtbl.replace docs u t;
                send_publish_diagnostics stdout ~uri:u
                  ~diagnostics:(parse_diagnostics_for_text ~uri:u ~text:t)
            | _ -> ())
        | Some "textDocument/didChange" -> (
            let uri = get_text_document_uri params in
            let text = get_did_change_text params in
            match (uri, text) with
            | Some u, Some t ->
                Hashtbl.replace docs u t;
                send_publish_diagnostics stdout ~uri:u
                  ~diagnostics:(parse_diagnostics_for_text ~uri:u ~text:t)
            | _ -> ())
        | Some "textDocument/didSave" -> (
            match get_text_document_uri params with
            | Some u -> (
                let text = Option.value (Hashtbl.find_opt docs u) ~default:"" in
                send_publish_diagnostics stdout ~uri:u
                  ~diagnostics:(parse_diagnostics_for_text ~uri:u ~text))
            | None -> ())
        | Some "textDocument/didClose" -> (
            match get_text_document_uri params with
            | Some u ->
                Hashtbl.remove docs u;
                send_publish_diagnostics stdout ~uri:u ~diagnostics:[]
            | None -> ())
        | Some "textDocument/hover" ->
            Option.iter
              (fun id ->
                let res =
                  match (get_text_document_uri params, position_from_params params) with
                  | Some u, Some (l, c) -> (
                      match Hashtbl.find_opt docs u with
                      | Some text -> (
                          match (Lsp_services.identifier_at text l c, parse_program_from_text text) with
                          | Some ident, Some p ->
                              let syms = semantic_symbols_of_program p in
                              (match Lsp_services.symbol_kind syms ident with
                              | None -> `Null
                              | Some kind ->
                                  let occ = List.length (find_identifier_occurrences text ident) in
                                  `Assoc
                                    [
                                      ( "contents",
                                        `Assoc
                                          [
                                            ("kind", `String "markdown");
                                            ( "value",
                                              `String
                                                (Printf.sprintf "`%s` (%s)\n\nOccurrences in file: %d"
                                                   ident kind occ) );
                                          ] );
                                    ])
                          | _ -> `Null)
                      | None -> `Null)
                  | _ -> `Null
                in
                send_result stdout ~id_json:id ~result_json:res)
              id_json
        | Some "textDocument/definition" ->
            Option.iter
              (fun id ->
                let res =
                  match (get_text_document_uri params, position_from_params params) with
                  | Some u, Some (l, c) -> (
                      match Hashtbl.find_opt docs u with
                      | Some text -> (
                          match (Lsp_services.identifier_at text l c, parse_program_from_text text) with
                          | Some ident, Some p ->
                              let syms = semantic_symbols_of_program p in
                              (match Lsp_services.symbol_kind syms ident with
                              | None -> `Null
                              | Some _ ->
                                  (match first_definition_position ~text ~ident ~symbols:syms with
                                  | Some (dl, dc1, dc2) ->
                                      `Assoc
                                        [
                                          ("uri", `String u);
                                          ("range", range_json ~line:dl ~c1:dc1 ~c2:dc2);
                                        ]
                                  | None -> `Null))
                          | _ -> `Null)
                      | None -> `Null)
                  | _ -> `Null
                in
                send_result stdout ~id_json:id ~result_json:res)
              id_json
        | Some "textDocument/references" ->
            Option.iter
              (fun id ->
                let refs =
                  match (get_text_document_uri params, position_from_params params) with
                  | Some u, Some (l, c) -> (
                      match Hashtbl.find_opt docs u with
                      | Some text -> (
                          match (Lsp_services.identifier_at text l c, parse_program_from_text text) with
                          | Some ident, Some p ->
                              let syms = semantic_symbols_of_program p in
                              (match Lsp_services.symbol_kind syms ident with
                              | None -> []
                              | Some _ ->
                                  find_identifier_occurrences text ident
                                  |> List.map (fun (rl, rc1, rc2) ->
                                         `Assoc
                                           [
                                             ("uri", `String u);
                                             ("range", range_json ~line:rl ~c1:rc1 ~c2:rc2);
                                           ]))
                          | _ -> [])
                      | None -> [])
                  | _ -> []
                in
                send_result stdout ~id_json:id ~result_json:(`List refs))
              id_json
        | Some "textDocument/completion" ->
            Option.iter
              (fun id ->
                let items =
                  match get_text_document_uri params with
                  | Some u -> (
                      match Hashtbl.find_opt docs u with
                      | None -> []
                      | Some text ->
                          Lsp_services.completion_items_for_text text
                          |> List.map (fun s ->
                                 `Assoc
                                   [
                                     ("label", `String s);
                                     ("kind", `Int 6);
                                     ("insertText", `String s);
                                   ]))
                  | None -> []
                in
                send_result stdout ~id_json:id
                  ~result_json:(`Assoc [ ("isIncomplete", `Bool false); ("items", `List items) ]))
              id_json
        | Some "textDocument/documentSymbol" ->
            Option.iter
              (fun id ->
                let syms =
                  match get_text_document_uri params with
                  | Some u -> (
                      match Hashtbl.find_opt docs u with
                      | Some text ->
                          Lsp_services.document_symbols_for_text text
                          |> List.map (fun s ->
                                 symbol_info ~uri:u ~name:s.Lsp_services.name ~line:s.line
                                   ~character:s.character)
                      | None -> [])
                  | None -> []
                in
                send_result stdout ~id_json:id ~result_json:(`List syms))
              id_json
        | Some "workspace/symbol" ->
            Option.iter (fun id -> send_result stdout ~id_json:id ~result_json:(`List [])) id_json
        | Some "textDocument/formatting" ->
            Option.iter
              (fun id ->
                let edits =
                  match get_text_document_uri params with
                  | Some u -> (
                      match Hashtbl.find_opt docs u with
                      | Some text ->
                          let lines = String.split_on_char '\n' text in
                          let line_count = max 1 (List.length lines) in
                          let new_text = Lsp_services.format_text text in
                          if new_text = text then [] else
                            [
                              `Assoc
                                [
                                  ( "range",
                                    `Assoc
                                      [
                                        ("start", `Assoc [ ("line", `Int 0); ("character", `Int 0) ]);
                                        ("end", `Assoc [ ("line", `Int line_count); ("character", `Int 0) ]);
                                      ] );
                                  ("newText", `String new_text);
                                ];
                            ]
                      | None -> [])
                  | None -> []
                in
                send_result stdout ~id_json:id ~result_json:(`List edits))
              id_json
        | Some "kairos/outline" ->
            Option.iter
              (fun id ->
                let uri = get_param_string params "uri" in
                let source_text =
                  match uri with
                  | Some u -> Option.value (Hashtbl.find_opt docs u) ~default:""
                  | None -> Option.value (get_param_string params "sourceText") ~default:""
                in
                let abstract_text =
                  Option.value (get_param_string params "abstractText") ~default:""
                in
                let res =
                  `Assoc
                    [
                      ("source", yojson_of_outline_sections (outline_sections_of_text source_text));
                      ( "abstract",
                        yojson_of_outline_sections (outline_sections_of_text abstract_text) );
                    ]
                in
                send_result stdout ~id_json:id ~result_json:res)
              id_json
        | Some "kairos/goalsTreeFinal" ->
            Option.iter
              (fun id ->
                let goals_json = Option.value (get_param_list params "goals") ~default:[] in
                let vc_sources_json =
                  Option.value (get_param_list params "vcSources") ~default:[]
                in
                let vc_text = Option.value (get_param_string params "vcText") ~default:"" in
                let goals =
                  List.filter_map (fun g -> match Lsp_protocol.goal_info_of_yojson g with Ok v -> Some v | Error _ -> None) goals_json
                in
                let vc_sources =
                  List.filter_map
                    (function `List [ `Int k; `String v ] -> Some (k, v) | _ -> None)
                    vc_sources_json
                in
                let nodes = Lsp_services.goals_tree_final ~goals ~vc_sources ~vc_text in
                send_result stdout ~id_json:id
                  ~result_json:(goals_tree_json_of_nodes nodes))
              id_json
        | Some "kairos/goalsTreePending" ->
            Option.iter
              (fun id ->
                let goal_names =
                  Option.value (get_param_list params "goalNames") ~default:[]
                  |> List.filter_map (function `String s -> Some s | _ -> None)
                in
                let vc_ids =
                  Option.value (get_param_list params "vcIds") ~default:[]
                  |> List.filter_map (function `Int i -> Some i | _ -> None)
                in
                let vc_sources_json =
                  Option.value (get_param_list params "vcSources") ~default:[]
                in
                let vc_sources =
                  List.filter_map
                    (function `List [ `Int k; `String v ] -> Some (k, v) | _ -> None)
                    vc_sources_json
                in
                let nodes =
                  Lsp_services.goals_tree_pending ~goal_names ~vc_ids ~vc_sources
                in
                send_result stdout ~id_json:id
                  ~result_json:(goals_tree_json_of_nodes nodes))
              id_json
        | Some "kairos/instrumentationPass" ->
            Option.iter
              (fun id ->
                match get_param_string params "inputFile" with
                | Some input_file when Sys.file_exists input_file -> (
                    match Engine_service.instrumentation_pass ~engine:(get_engine params)
                            ~generate_png:(get_param_bool params "generatePng" true) ~input_file
                    with
                    | Ok out ->
                        send_result stdout ~id_json:id
                          ~result_json:(Lsp_protocol.yojson_of_automata_outputs (map_automata out))
                    | Error e ->
                        send_error stdout ~id_json:(Some id) ~code:(-32001) ~message:(Pipeline.error_to_string e))
                | _ ->
                    send_error stdout ~id_json:(Some id) ~code:(-32602)
                      ~message:"Missing valid inputFile for kairos/instrumentationPass")
              id_json
        | Some "kairos/obcPass" ->
            Option.iter
              (fun id ->
                match get_param_string params "inputFile" with
                | Some input_file when Sys.file_exists input_file -> (
                    match Engine_service.obc_pass ~engine:(get_engine params) ~input_file with
                    | Ok out ->
                        send_result stdout ~id_json:id ~result_json:(Lsp_protocol.yojson_of_obc_outputs (map_obc out))
                    | Error e -> send_error stdout ~id_json:(Some id) ~code:(-32001) ~message:(Pipeline.error_to_string e))
                | _ -> send_error stdout ~id_json:(Some id) ~code:(-32602) ~message:"Missing valid inputFile")
              id_json
        | Some "kairos/whyPass" ->
            Option.iter
              (fun id ->
                match get_param_string params "inputFile" with
                | Some input_file when Sys.file_exists input_file -> (
                    match
                      Engine_service.why_pass ~engine:(get_engine params)
                        ~prefix_fields:(get_param_bool params "prefixFields" false) ~input_file
                    with
                    | Ok out ->
                        send_result stdout ~id_json:id ~result_json:(Lsp_protocol.yojson_of_why_outputs (map_why out))
                    | Error e -> send_error stdout ~id_json:(Some id) ~code:(-32001) ~message:(Pipeline.error_to_string e))
                | _ -> send_error stdout ~id_json:(Some id) ~code:(-32602) ~message:"Missing valid inputFile")
              id_json
        | Some "kairos/obligationsPass" ->
            Option.iter
              (fun id ->
                match (get_param_string params "inputFile", get_param_string params "prover") with
                | Some input_file, Some prover when Sys.file_exists input_file -> (
                    match
                      Engine_service.obligations_pass ~engine:(get_engine params)
                        ~prefix_fields:(get_param_bool params "prefixFields" false) ~prover ~input_file
                    with
                    | Ok out ->
                        send_result stdout ~id_json:id
                          ~result_json:(Lsp_protocol.yojson_of_obligations_outputs (map_oblig out))
                    | Error e -> send_error stdout ~id_json:(Some id) ~code:(-32001) ~message:(Pipeline.error_to_string e))
                | _ -> send_error stdout ~id_json:(Some id) ~code:(-32602) ~message:"Missing valid inputFile/prover")
              id_json
        | Some "kairos/evalPass" ->
            Option.iter
              (fun id ->
                match (get_param_string params "inputFile", get_param_string params "traceText") with
                | Some input_file, Some trace_text when Sys.file_exists input_file -> (
                    match
                      Engine_service.eval_pass ~engine:(get_engine params) ~input_file ~trace_text
                        ~with_state:(get_param_bool params "withState" false)
                        ~with_locals:(get_param_bool params "withLocals" false)
                    with
                    | Ok out -> send_result stdout ~id_json:id ~result_json:(`String out)
                    | Error e -> send_error stdout ~id_json:(Some id) ~code:(-32001) ~message:(Pipeline.error_to_string e))
                | _ -> send_error stdout ~id_json:(Some id) ~code:(-32602) ~message:"Missing valid inputFile/traceText")
              id_json
        | Some "kairos/dotPngFromText" ->
            Option.iter
              (fun id ->
                match get_param_string params "dotText" with
                | Some dot ->
                    let out = Pipeline.dot_png_from_text dot in
                    send_result stdout ~id_json:id
                      ~result_json:(match out with None -> `Null | Some s -> `String s)
                | None -> send_error stdout ~id_json:(Some id) ~code:(-32602) ~message:"Missing dotText")
              id_json
        | Some "kairos/run" ->
            Option.iter
              (fun id ->
                let req_key = id_key id in
                if Hashtbl.mem canceled req_key then
                  send_error stdout ~id_json:(Some id) ~code:(-32800) ~message:"Request cancelled"
                else
                match get_param_string params "inputFile" with
                | Some input_file when Sys.file_exists input_file ->
                    let progress_token = "kairos-run-" ^ string_of_int !next_server_req_id in
                    if !supports_work_done_progress then (
                      send_request stdout ~id_json:(`Int !next_server_req_id)
                        ~method_name:"window/workDoneProgress/create"
                        ~params_json:(`Assoc [ ("token", `String progress_token) ]);
                      incr next_server_req_id;
                      send_work_done_begin stdout ~token:progress_token ~title:"Kairos run"
                        ~message:"Starting");
                    let cfg : Pipeline.config =
                      {
                        input_file;
                        prover = Option.value (get_param_string params "prover") ~default:"z3";
                        prover_cmd = get_param_string params "proverCmd";
                        wp_only = get_param_bool params "wpOnly" false;
                        smoke_tests = get_param_bool params "smokeTests" false;
                        timeout_s = get_param_int params "timeoutS" 5;
                        prefix_fields = get_param_bool params "prefixFields" false;
                        prove = get_param_bool params "prove" true;
                        generate_vc_text = get_param_bool params "generateVcText" true;
                        generate_smt_text = get_param_bool params "generateSmtText" true;
                        generate_monitor_text = get_param_bool params "generateMonitorText" true;
                        generate_dot_png = get_param_bool params "generateDotPng" true;
                      }
                    in
                    let engine = get_engine params in
                    let on_outputs_ready out =
                      if !supports_work_done_progress then
                        send_work_done_report stdout ~token:progress_token ~message:"Outputs ready";
                      send_notification stdout ~method_name:"kairos/outputsReady"
                        ~params_json:
                          (`Assoc [ ("requestId", id); ("payload", Lsp_protocol.yojson_of_outputs (map_outputs out)) ])
                    in
                    let on_goals_ready (names, vc_ids) =
                      send_notification stdout ~method_name:"kairos/goalsReady"
                        ~params_json:
                          (`Assoc
                            [ ("requestId", id);
                              ("payload", `Assoc [ ("names", `List (List.map (fun s -> `String s) names)); ("vcIds", `List (List.map (fun i -> `Int i) vc_ids)) ]) ])
                    in
                    let on_goal_done idx goal status time_s dump_path source vcid =
                      send_notification stdout ~method_name:"kairos/goalDone"
                        ~params_json:
                          (`Assoc
                            [ ("requestId", id);
                              ("payload",
                               `Assoc
                                 [ ("idx", `Int idx); ("goal", `String goal); ("status", `String status);
                                   ("time_s", `Float time_s);
                                   ("dump_path", Option.value (Option.map (fun s -> `String s) dump_path) ~default:`Null);
                                   ("source", `String source);
                                   ("vcid", Option.value (Option.map (fun s -> `String s) vcid) ~default:`Null) ]) ])
                    in
                    (match
                       Engine_service.run_with_callbacks ~engine
                         ~should_cancel:(fun () ->
                           Hashtbl.mem canceled req_key)
                         cfg ~on_outputs_ready ~on_goals_ready ~on_goal_done
                     with
                    | Ok out ->
                        if Hashtbl.mem canceled req_key then
                          send_error stdout ~id_json:(Some id) ~code:(-32800) ~message:"Request cancelled"
                        else (
                          if !supports_work_done_progress then
                            send_work_done_end stdout ~token:progress_token ~message:"Done";
                          send_result stdout ~id_json:id ~result_json:(Lsp_protocol.yojson_of_outputs (map_outputs out)))
                    | Error e -> send_error stdout ~id_json:(Some id) ~code:(-32001) ~message:(Pipeline.error_to_string e))
                | _ -> send_error stdout ~id_json:(Some id) ~code:(-32602) ~message:"Missing valid inputFile")
              id_json
        | Some _ ->
            Option.iter (fun id -> send_error stdout ~id_json:(Some id) ~code:(-32601) ~message:"Method not found") id_json
        | None ->
            Option.iter (fun id -> send_error stdout ~id_json:(Some id) ~code:(-32600) ~message:"Invalid request") id_json)
  done
