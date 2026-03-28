open Yojson.Safe

module Lsp_types = Lsp.Types

module Sync_io = struct
  type 'a t = 'a

  let return x = x
  let raise exn = Stdlib.raise exn

  module O = struct
    let ( let+ ) x f = f x
    let ( let* ) x f = f x
  end
end

module Channels = struct
  type input = in_channel
  type output = out_channel

  let read_line ic =
    try Some (input_line ic)
    with End_of_file -> None

  let read_exactly ic len =
    try Some (really_input_string ic len)
    with End_of_file -> None

  let write oc parts =
    List.iter (output_string oc) parts;
    flush oc
end

module Transport = Lsp.Io.Make (Sync_io) (Channels)

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

let send_packet (oc : out_channel) (packet : Jsonrpc.Packet.t) : unit =
  trace_line "lsp-server -> client" (Jsonrpc.Packet.yojson_of_t packet |> Yojson.Safe.to_string);
  Transport.write oc packet

let error_code_of_int = function
  | -32700 -> Jsonrpc.Response.Error.Code.ParseError
  | -32600 -> Jsonrpc.Response.Error.Code.InvalidRequest
  | -32601 -> Jsonrpc.Response.Error.Code.MethodNotFound
  | -32602 -> Jsonrpc.Response.Error.Code.InvalidParams
  | -32603 -> Jsonrpc.Response.Error.Code.InternalError
  | -32002 -> Jsonrpc.Response.Error.Code.ServerNotInitialized
  | -32800 -> Jsonrpc.Response.Error.Code.RequestCancelled
  | n -> Jsonrpc.Response.Error.Code.Other n

let send_result (oc : out_channel) ~(id_json : Jsonrpc.Id.t) ~(result_json : Yojson.Safe.t) : unit =
  send_packet oc (Jsonrpc.Packet.Response (Jsonrpc.Response.ok id_json result_json))

let send_error_raw (oc : out_channel) ~(id_json : Yojson.Safe.t option) ~(code : int) ~(message : string) :
    unit =
  let payload =
    `Assoc
      [
        ("jsonrpc", `String "2.0");
        ("id", Option.value id_json ~default:`Null);
        ("error", `Assoc [ ("code", `Int code); ("message", `String message) ]);
      ]
  in
  trace_line "lsp-server -> client" (Yojson.Safe.to_string payload);
  send_raw oc (Yojson.Safe.to_string payload)

let send_error (oc : out_channel) ~(id_json : Jsonrpc.Id.t option) ~(code : int) ~(message : string) : unit =
  match id_json with
  | Some id ->
      let error =
        Jsonrpc.Response.Error.make ~code:(error_code_of_int code) ~message ()
      in
      send_packet oc (Jsonrpc.Packet.Response (Jsonrpc.Response.error id error))
  | None -> send_error_raw oc ~id_json:None ~code ~message

let structured_of_json = function
  | (`Assoc _ | `List _) as json -> Some (Jsonrpc.Structured.t_of_yojson json)
  | _ -> None

let send_notification (oc : out_channel) ~(method_name : string) ~(params_json : Yojson.Safe.t) : unit =
  let params = structured_of_json params_json in
  send_packet oc
    (Jsonrpc.Packet.Notification (Jsonrpc.Notification.create ?params ~method_:method_name ()))

let send_request (oc : out_channel) ~(id_json : Jsonrpc.Id.t) ~(method_name : string)
    ~(params_json : Yojson.Safe.t) : unit =
  let params = structured_of_json params_json in
  send_packet oc
    (Jsonrpc.Packet.Request (Jsonrpc.Request.create ?params ~id:id_json ~method_:method_name ()))

let lsp_position ~line ~character = Lsp_types.Position.create ~line ~character

let lsp_range ~line ~c1 ~c2 =
  let start = lsp_position ~line ~character:c1 in
  let end_ = lsp_position ~line ~character:c2 in
  Lsp_types.Range.create ~start ~end_

let range_json ~line ~c1 ~c2 : Yojson.Safe.t =
  lsp_range ~line ~c1 ~c2 |> Lsp_types.Range.yojson_of_t

let lsp_location_json ~uri ~line ~c1 ~c2 : Yojson.Safe.t =
  Lsp_types.Location.create ~uri:(Lsp_types.DocumentUri.of_string uri) ~range:(lsp_range ~line ~c1 ~c2)
  |> Lsp_types.Location.yojson_of_t

let hover_json ~ident ~kind ~occurrences : Yojson.Safe.t =
  let value = Printf.sprintf "`%s` (%s)\n\nOccurrences in file: %d" ident kind occurrences in
  Lsp_types.Hover.create
    ~contents:(`MarkupContent (Lsp_types.MarkupContent.create ~kind:Lsp_types.MarkupKind.Markdown ~value))
    ()
  |> Lsp_types.Hover.yojson_of_t

let completion_item_json (label : string) : Yojson.Safe.t =
  Lsp_types.CompletionItem.create ~label ~kind:Lsp_types.CompletionItemKind.Function ~insertText:label ()
  |> Lsp_types.CompletionItem.yojson_of_t

let completion_list_json (items : Yojson.Safe.t list) : Yojson.Safe.t =
  let items =
    List.filter_map
      (fun json ->
        try Some (Lsp_types.CompletionItem.t_of_yojson json)
        with _ -> None)
      items
  in
  Lsp_types.CompletionList.create ~isIncomplete:false ~items () |> Lsp_types.CompletionList.yojson_of_t

let full_document_text_edit_json ~line_count ~new_text : Yojson.Safe.t =
  Lsp_types.TextEdit.create ~newText:new_text ~range:(lsp_range ~line:0 ~c1:0 ~c2:0)
  |> fun edit ->
  let range =
    let start = lsp_position ~line:0 ~character:0 in
    let end_ = lsp_position ~line:line_count ~character:0 in
    Lsp_types.Range.create ~start ~end_
  in
  { edit with range } |> Lsp_types.TextEdit.yojson_of_t

let protocol_request_id (id : Jsonrpc.Id.t) : Lsp_protocol.rpc_request_id =
  match Lsp_protocol.rpc_request_id_of_yojson (Jsonrpc.Id.yojson_of_t id) with
  | Ok request_id -> request_id
  | Error _ -> Lsp_protocol.Rpc_string_id (Jsonrpc.Id.yojson_of_t id |> Yojson.Safe.to_string)

let diagnostic_to_json (d : Lsp_services.diagnostic) : Yojson.Safe.t =
  let severity =
    match d.severity with
    | 1 -> Some Lsp_types.DiagnosticSeverity.Error
    | 2 -> Some Lsp_types.DiagnosticSeverity.Warning
    | 3 -> Some Lsp_types.DiagnosticSeverity.Information
    | 4 -> Some Lsp_types.DiagnosticSeverity.Hint
    | _ -> None
  in
  let range =
    let start = lsp_position ~line:d.line ~character:d.col in
    let end_ = lsp_position ~line:d.line ~character:(d.col + 1) in
    Lsp_types.Range.create ~start ~end_
  in
  Lsp_types.Diagnostic.create ~message:(`String d.message) ~range ?severity ~source:d.source ()
  |> Lsp_types.Diagnostic.yojson_of_t

let send_publish_diagnostics (oc : out_channel) ~(uri : string) ~(diagnostics : Yojson.Safe.t list) : unit =
  let diagnostics =
    List.filter_map
      (fun json ->
        try Some (Lsp_types.Diagnostic.t_of_yojson json)
        with _ -> None)
      diagnostics
  in
  let params =
    Lsp_types.PublishDiagnosticsParams.create ~uri:(Lsp_types.DocumentUri.of_string uri) ~diagnostics ()
  in
  send_notification oc ~method_name:"textDocument/publishDiagnostics"
    ~params_json:(Lsp_types.PublishDiagnosticsParams.yojson_of_t params)

let parse_diagnostics_for_text ~(uri : string) ~(text : string) : Yojson.Safe.t list =
  Lsp_services.diagnostics_for_text ~uri ~text |> List.map diagnostic_to_json

let find_identifier_occurrences = Lsp_services.identifier_occurrences
type semantic_symbols = Lsp_services.semantic_symbols
let semantic_symbols_of_program = Lsp_services.semantic_symbols_of_program
let parse_program_from_text = Lsp_services.parse_program_from_text
let first_definition_position = Lsp_services.first_definition_position
let position_from_params = Lsp_app.position_from_params
let map_outputs = Lsp_app.map_outputs
let map_automata = Lsp_app.map_automata
let map_why = Lsp_app.map_why
let map_oblig = Lsp_app.map_oblig
let get_param_string = Lsp_app.get_param_string
let get_param_bool = Lsp_app.get_param_bool
let get_param_int = Lsp_app.get_param_int
let get_param_list = Lsp_app.get_param_list
let get_text_document_uri = Lsp_app.get_text_document_uri
let get_did_open_text = Lsp_app.get_did_open_text
let get_did_change_text = Lsp_app.get_did_change_text
let client_supports_work_done_progress = Lsp_app.client_supports_work_done_progress

let get_engine (params : Yojson.Safe.t) : Engine_service.engine =
  match get_param_string params "engine" with
  | Some s -> Option.value (Engine_service.engine_of_string s) ~default:Engine_service.Default
  | None -> Engine_service.Default

let symbol_info ~(uri : string) ~(name : string) ~(line : int) ~(character : int) : Yojson.Safe.t =
  let range =
    let start = lsp_position ~line ~character in
    let end_ = lsp_position ~line ~character:(character + 1) in
    Lsp_types.Range.create ~start ~end_
  in
  let location = Lsp_types.Location.create ~uri:(Lsp_types.DocumentUri.of_string uri) ~range in
  Lsp_types.SymbolInformation.create ~name ~kind:Lsp_types.SymbolKind.Function ~location ()
  |> Lsp_types.SymbolInformation.yojson_of_t

type outline_sections = Lsp_services.outline_sections
let outline_sections_of_text = Lsp_services.outline_sections_of_text

let yojson_of_outline_sections = Lsp_services.yojson_of_outline_sections

let goals_tree_json_of_nodes = Lsp_services.yojson_of_goals_tree

let decode_or_none decode json =
  match decode json with
  | Ok value -> Some value
  | Error _ -> None

let kobj_request_input_and_engine (params : Yojson.Safe.t) :
    (string option * Engine_service.engine) =
  let req = decode_or_none Lsp_protocol.kobj_summary_request_of_yojson params in
  let input_file =
    match req with
    | Some req -> Some req.input_file
    | None -> get_param_string params "inputFile"
  in
  let engine =
    match req with
    | Some req -> Option.value (Engine_service.engine_of_string req.engine) ~default:Engine_service.Default
    | None -> get_engine params
  in
  (input_file, engine)

let pipeline_config_of_protocol = Lsp_backend.pipeline_config_of_protocol

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

let member k = function `Assoc xs -> List.assoc_opt k xs | _ -> None
let as_string = function Some (`String s) -> Some s | _ -> None
let is_request id_json = Option.is_some id_json
let id_key (id : Jsonrpc.Id.t) = Jsonrpc.Id.yojson_of_t id |> Yojson.Safe.to_string

let () =
  let docs : (string, string) Hashtbl.t = Hashtbl.create 32 in
  let canceled : (string, unit) Hashtbl.t = Hashtbl.create 64 in
  let next_server_req_id = ref 1 in
  let initialized = ref false in
  let shutdown_requested = ref false in
  let supports_work_done_progress = ref false in
  let running = ref true in
  while !running do
    let packet =
      try Transport.read stdin
      with _ ->
        send_error_raw stdout ~id_json:None ~code:(-32700) ~message:"Parse error";
        None
    in
    match packet with
    | None -> running := false
    | Some (Jsonrpc.Packet.Response _) | Some (Jsonrpc.Packet.Batch_response _) -> ()
    | Some (Jsonrpc.Packet.Batch_call _) ->
        send_error_raw stdout ~id_json:None ~code:(-32600) ~message:"Batch requests are not supported"
    | Some packet -> (
        let method_name, id_json, params =
          match packet with
          | Jsonrpc.Packet.Request req ->
              trace_line "client -> lsp-server"
                (Jsonrpc.Packet.yojson_of_t packet |> Yojson.Safe.to_string);
              ( Some req.method_,
                Some req.id,
                match req.params with None -> `Assoc [] | Some p -> (p :> Yojson.Safe.t) )
          | Jsonrpc.Packet.Notification notif ->
              trace_line "client -> lsp-server"
                (Jsonrpc.Packet.yojson_of_t packet |> Yojson.Safe.to_string);
              ( Some notif.method_,
                None,
                match notif.params with None -> `Assoc [] | Some p -> (p :> Yojson.Safe.t) )
          | _ -> (None, None, `Assoc [])
        in
        match method_name with
        | Some "initialize" when !initialized ->
            if is_request id_json then
              send_error stdout ~id_json ~code:(-32600) ~message:"Server already initialized"
        | Some "initialize" ->
            initialized := true;
            supports_work_done_progress := client_supports_work_done_progress params;
            let result =
              let capabilities =
                Lsp_types.ServerCapabilities.create
                  ~textDocumentSync:
                    (`TextDocumentSyncOptions
                      (Lsp_types.TextDocumentSyncOptions.create ~openClose:true
                         ~change:Lsp_types.TextDocumentSyncKind.Full
                         ~save:(`SaveOptions (Lsp_types.SaveOptions.create ~includeText:false ()))
                         ()))
                  ~hoverProvider:(`Bool true)
                  ~definitionProvider:(`Bool true)
                  ~referencesProvider:(`Bool true)
                  ~documentSymbolProvider:(`Bool true)
                  ~completionProvider:(Lsp_types.CompletionOptions.create ~triggerCharacters:[] ())
                  ~workspaceSymbolProvider:(`Bool true)
                  ~documentFormattingProvider:(`Bool true) ()
              in
              Lsp_types.InitializeResult.create ~capabilities
                ~serverInfo:(Lsp_types.InitializeResult.create_serverInfo ~name:"kairos-lsp" ~version:"1.0" ())
                ()
              |> Lsp_types.InitializeResult.yojson_of_t
            in
            Option.iter (fun id -> send_result stdout ~id_json:id ~result_json:result) id_json
        | Some "initialized" when not !initialized -> ()
        | Some "initialized" -> ()
        | Some "$/cancelRequest" -> (
            match params with
            | `Assoc xs -> (
                match List.assoc_opt "id" xs with
                | Some cid -> (
                    try Hashtbl.replace canceled (id_key (Jsonrpc.Id.t_of_yojson cid)) ()
                    with _ -> ())
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
                                  hover_json ~ident ~kind ~occurrences:occ)
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
                                      lsp_location_json ~uri:u ~line:dl ~c1:dc1 ~c2:dc2
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
                                         lsp_location_json ~uri:u ~line:rl ~c1:rc1 ~c2:rc2))
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
                          |> List.map completion_item_json)
                  | None -> []
                in
                send_result stdout ~id_json:id ~result_json:(completion_list_json items))
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
                            [ full_document_text_edit_json ~line_count ~new_text ]
                      | None -> [])
                  | None -> []
                in
                send_result stdout ~id_json:id ~result_json:(`List edits))
              id_json
        | Some "kairos/outline" ->
            Option.iter
              (fun id ->
                let req = decode_or_none Lsp_protocol.outline_request_of_yojson params in
                let uri =
                  match req with
                  | Some req -> req.uri
                  | None -> get_param_string params "uri"
                in
                let source_text =
                  match (req, uri) with
                  | Some req, _ -> Option.value req.source_text ~default:""
                  | None, Some u -> Option.value (Hashtbl.find_opt docs u) ~default:""
                  | None, None -> Option.value (get_param_string params "sourceText") ~default:""
                in
                let abstract_text =
                  match req with
                  | Some req -> Option.value req.abstract_text ~default:""
                  | None -> Option.value (get_param_string params "abstractText") ~default:""
                in
                let res =
                  Lsp_protocol.yojson_of_outline_payload
                    {
                      source =
                        {
                          nodes = (outline_sections_of_text source_text).nodes;
                          transitions = (outline_sections_of_text source_text).transitions;
                          contracts = (outline_sections_of_text source_text).contracts;
                        };
                      abstract_program =
                        {
                          nodes = (outline_sections_of_text abstract_text).nodes;
                          transitions = (outline_sections_of_text abstract_text).transitions;
                          contracts = (outline_sections_of_text abstract_text).contracts;
                        };
                    }
                in
                send_result stdout ~id_json:id ~result_json:res)
              id_json
        | Some "kairos/goalsTreeFinal" ->
            Option.iter
              (fun id ->
                match decode_or_none Lsp_protocol.goals_tree_final_request_of_yojson params with
                | Some req ->
                    let nodes =
                      Lsp_services.goals_tree_final ~goals:req.goals ~vc_sources:req.vc_sources
                        ~vc_text:req.vc_text
                    in
                    send_result stdout ~id_json:id
                      ~result_json:(goals_tree_json_of_nodes nodes)
                | None ->
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
                match decode_or_none Lsp_protocol.goals_tree_pending_request_of_yojson params with
                | Some req ->
                    let nodes =
                      Lsp_services.goals_tree_pending ~goal_names:req.goal_names ~vc_ids:req.vc_ids
                        ~vc_sources:req.vc_sources
                    in
                    send_result stdout ~id_json:id
                      ~result_json:(goals_tree_json_of_nodes nodes)
                | None ->
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
                let req = decode_or_none Lsp_protocol.instrumentation_pass_request_of_yojson params in
                let req =
                  match req with
                  | Some req -> Some req
                  | None -> (
                      match get_param_string params "inputFile" with
                      | Some input_file ->
                          Some
                            {
                              Lsp_protocol.input_file;
                              generate_png = get_param_bool params "generatePng" true;
                              engine = Engine_service.string_of_engine (get_engine params);
                            }
                      | None -> None)
                in
                match req with
                | Some req when Sys.file_exists req.input_file -> (
                    match Lsp_backend.instrumentation_pass req with
                    | Ok out ->
                        send_result stdout ~id_json:id
                          ~result_json:(Lsp_protocol.yojson_of_automata_outputs out)
                    | Error msg ->
                        send_error stdout ~id_json:(Some id) ~code:(-32001) ~message:msg)
                | _ ->
                    send_error stdout ~id_json:(Some id) ~code:(-32602)
                      ~message:"Missing valid inputFile for kairos/instrumentationPass")
              id_json
        | Some "kairos/whyPass" ->
            Option.iter
              (fun id ->
                let req = decode_or_none Lsp_protocol.why_pass_request_of_yojson params in
                let req =
                  match req with
                  | Some req -> Some req
                  | None -> (
                      match get_param_string params "inputFile" with
                      | Some input_file ->
                          Some
                            {
                              Lsp_protocol.input_file;
                              prefix_fields = get_param_bool params "prefixFields" false;
                              engine = Engine_service.string_of_engine (get_engine params);
                            }
                      | None -> None)
                in
                match req with
                | Some req when Sys.file_exists req.input_file -> (
                    match Lsp_backend.why_pass req with
                    | Ok out ->
                        send_result stdout ~id_json:id
                          ~result_json:(Lsp_protocol.yojson_of_why_outputs out)
                    | Error msg ->
                        send_error stdout ~id_json:(Some id) ~code:(-32001) ~message:msg)
                | _ ->
                    send_error stdout ~id_json:(Some id) ~code:(-32602)
                      ~message:"Missing valid inputFile")
              id_json
        | Some "kairos/obligationsPass" ->
            Option.iter
              (fun id ->
                let req = decode_or_none Lsp_protocol.obligations_pass_request_of_yojson params in
                let req =
                  match req with
                  | Some req -> Some req
                  | None -> (
                      match (get_param_string params "inputFile", get_param_string params "prover") with
                      | Some input_file, Some prover ->
                          Some
                            {
                              Lsp_protocol.input_file;
                              prover;
                              prefix_fields = get_param_bool params "prefixFields" false;
                              engine = Engine_service.string_of_engine (get_engine params);
                            }
                      | _ -> None)
                in
                match req with
                | Some req when Sys.file_exists req.input_file -> (
                    match Lsp_backend.obligations_pass req with
                    | Ok out ->
                        send_result stdout ~id_json:id
                          ~result_json:(Lsp_protocol.yojson_of_obligations_outputs out)
                    | Error msg ->
                        send_error stdout ~id_json:(Some id) ~code:(-32001) ~message:msg)
                | _ ->
                    send_error stdout ~id_json:(Some id) ~code:(-32602)
                      ~message:"Missing valid inputFile/prover")
              id_json
        | Some "kairos/evalPass" ->
            Option.iter
              (fun id ->
                let req = decode_or_none Lsp_protocol.eval_pass_request_of_yojson params in
                let req =
                  match req with
                  | Some req -> Some req
                  | None -> (
                      match (get_param_string params "inputFile", get_param_string params "traceText") with
                      | Some input_file, Some trace_text ->
                          Some
                            {
                              Lsp_protocol.input_file;
                              trace_text;
                              with_state = get_param_bool params "withState" false;
                              with_locals = get_param_bool params "withLocals" false;
                              engine = Engine_service.string_of_engine (get_engine params);
                            }
                      | _ -> None)
                in
                match req with
                | Some req when Sys.file_exists req.input_file -> (
                    match Lsp_backend.eval_pass req with
                    | Ok out -> send_result stdout ~id_json:id ~result_json:(`String out)
                    | Error msg ->
                        send_error stdout ~id_json:(Some id) ~code:(-32001) ~message:msg)
                | _ ->
                    send_error stdout ~id_json:(Some id) ~code:(-32602)
                      ~message:"Missing valid inputFile/traceText")
              id_json
        | Some "kairos/kobjSummary" ->
            Option.iter
              (fun id ->
                let input_file, engine = kobj_request_input_and_engine params in
                match input_file with
                | Some input_file when Sys.file_exists input_file -> (
                    match
                      Lsp_backend.kobj_summary
                        { Lsp_protocol.input_file; engine = Engine_service.string_of_engine engine }
                    with
                    | Ok out -> send_result stdout ~id_json:id ~result_json:(`String out)
                    | Error msg ->
                        send_error stdout ~id_json:(Some id) ~code:(-32001) ~message:msg)
                | _ ->
                    send_error stdout ~id_json:(Some id) ~code:(-32602)
                      ~message:"Missing valid inputFile")
              id_json
        | Some "kairos/kobjClauses" ->
            Option.iter
              (fun id ->
                let input_file, engine = kobj_request_input_and_engine params in
                match input_file with
                | Some input_file when Sys.file_exists input_file -> (
                    match
                      Lsp_backend.kobj_clauses
                        { Lsp_protocol.input_file; engine = Engine_service.string_of_engine engine }
                    with
                    | Ok out -> send_result stdout ~id_json:id ~result_json:(`String out)
                    | Error msg ->
                        send_error stdout ~id_json:(Some id) ~code:(-32001) ~message:msg)
                | _ ->
                    send_error stdout ~id_json:(Some id) ~code:(-32602)
                      ~message:"Missing valid inputFile")
              id_json
        | Some "kairos/kobjProduct" ->
            Option.iter
              (fun id ->
                let input_file, engine = kobj_request_input_and_engine params in
                match input_file with
                | Some input_file when Sys.file_exists input_file -> (
                    match
                      Lsp_backend.kobj_product
                        { Lsp_protocol.input_file; engine = Engine_service.string_of_engine engine }
                    with
                    | Ok out -> send_result stdout ~id_json:id ~result_json:(`String out)
                    | Error msg ->
                        send_error stdout ~id_json:(Some id) ~code:(-32001) ~message:msg)
                | _ ->
                    send_error stdout ~id_json:(Some id) ~code:(-32602)
                      ~message:"Missing valid inputFile")
              id_json
        | Some "kairos/dotPngFromText" ->
            Option.iter
              (fun id ->
                let dot =
                  match decode_or_none Lsp_protocol.dot_png_from_text_request_of_yojson params with
                  | Some req -> Some req.dot_text
                  | None -> get_param_string params "dotText"
                in
                match dot with
                | Some dot ->
                    let out =
                      Lsp_backend.dot_png_from_text { Lsp_protocol.dot_text = dot }
                    in
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
                let cfg_from_protocol = decode_or_none Lsp_protocol.config_of_yojson params in
                let input_file =
                  match cfg_from_protocol with
                  | Some cfg -> Some cfg.input_file
                  | None -> get_param_string params "inputFile"
                in
                match input_file with
                | Some input_file when Sys.file_exists input_file ->
                    let progress_token = "kairos-run-" ^ string_of_int !next_server_req_id in
                    if !supports_work_done_progress then (
                      send_request stdout ~id_json:(`Int !next_server_req_id)
                        ~method_name:"window/workDoneProgress/create"
                        ~params_json:(`Assoc [ ("token", `String progress_token) ]);
                      incr next_server_req_id;
                      send_work_done_begin stdout ~token:progress_token ~title:"Kairos run"
                        ~message:"Starting");
                    let cfg : Pipeline_types.config =
                      match cfg_from_protocol with
                      | Some cfg ->
                          let cfg = pipeline_config_of_protocol cfg in
                          { cfg with input_file }
                      | None ->
                          {
                            input_file;
                            prover = Option.value (get_param_string params "prover") ~default:"z3";
                            prover_cmd = get_param_string params "proverCmd";
                            wp_only = get_param_bool params "wpOnly" false;
                            smoke_tests = get_param_bool params "smokeTests" false;
                            timeout_s = get_param_int params "timeoutS" 5;
                            selected_goal_index =
                              (match get_param_int params "selectedGoalIndex" (-1) with
                              | n when n >= 0 -> Some n
                              | _ -> None);
                            compute_proof_diagnostics =
                              get_param_bool params "computeProofDiagnostics" false;
                            prefix_fields = get_param_bool params "prefixFields" false;
                            prove = get_param_bool params "prove" true;
                            generate_vc_text = get_param_bool params "generateVcText" true;
                            generate_smt_text = get_param_bool params "generateSmtText" true;
                            generate_dot_png = get_param_bool params "generateDotPng" true;
                          }
                    in
                    let engine =
                      match cfg_from_protocol with
                      | Some cfg -> Option.value (Engine_service.engine_of_string cfg.engine) ~default:Engine_service.Default
                      | None -> get_engine params
                    in
                    if !supports_work_done_progress then
                      send_work_done_report stdout ~token:progress_token
                        ~message:
                          (if cfg.prove then "Building proof artifacts (OBC+/Why/VC) ..."
                           else "Building Kairos artifacts ...");
                    let completed_goals = ref 0 in
                    let total_goals = ref 0 in
                    let on_outputs_ready out =
                      if !supports_work_done_progress then
                        send_work_done_report stdout ~token:progress_token
                          ~message:
                            (if cfg.prove then
                               "Artifacts ready; publishing proof goals and solver results ..."
                             else "Artifacts ready");
                      let payload : Lsp_protocol.outputs_ready_notification =
                        {
                          request_id = protocol_request_id id;
                          payload = out;
                        }
                      in
                      send_notification stdout ~method_name:"kairos/outputsReady"
                        ~params_json:(Lsp_protocol.yojson_of_outputs_ready_notification payload)
                    in
                    let on_goals_ready (names, vc_ids) =
                      total_goals := max (List.length names) (List.length vc_ids);
                      if !supports_work_done_progress then
                        send_work_done_report stdout ~token:progress_token
                          ~message:
                            (if !total_goals > 0 then
                               Printf.sprintf "Publishing %d proof goals ..." !total_goals
                             else "Publishing proof goals ...");
                      let payload : Lsp_protocol.goals_ready_notification =
                        {
                          request_id = protocol_request_id id;
                          payload = { names; vc_ids };
                        }
                      in
                      send_notification stdout ~method_name:"kairos/goalsReady"
                        ~params_json:(Lsp_protocol.yojson_of_goals_ready_notification payload)
                    in
                    let on_goal_done idx goal status time_s dump_path source vcid =
                      incr completed_goals;
                      if !supports_work_done_progress then
                        send_work_done_report stdout ~token:progress_token
                          ~message:
                            (if !total_goals > 0 then
                               Printf.sprintf "Goal %d/%d: %s" !completed_goals !total_goals status
                             else Printf.sprintf "Goal %d: %s" (idx + 1) status);
                      let payload : Lsp_protocol.goal_done_notification =
                        {
                          request_id = protocol_request_id id;
                          payload = { idx; goal; status; time_s; dump_path; source; vcid };
                        }
                      in
                      send_notification stdout ~method_name:"kairos/goalDone"
                        ~params_json:(Lsp_protocol.yojson_of_goal_done_notification payload)
                    in
                    let lsp_cfg =
                      {
                        Lsp_protocol.input_file = cfg.input_file;
                        engine = Engine_service.string_of_engine engine;
                        prover = cfg.prover;
                        prover_cmd = cfg.prover_cmd;
                        wp_only = cfg.wp_only;
                        smoke_tests = cfg.smoke_tests;
                        timeout_s = cfg.timeout_s;
                        selected_goal_index = cfg.selected_goal_index;
                        compute_proof_diagnostics = cfg.compute_proof_diagnostics;
                        prefix_fields = cfg.prefix_fields;
                        prove = cfg.prove;
                        generate_vc_text = cfg.generate_vc_text;
                        generate_smt_text = cfg.generate_smt_text;
                        generate_dot_png = cfg.generate_dot_png;
                      }
                    in
                    (match
                       Lsp_backend.run_with_callbacks ~engine
                         ~should_cancel:(fun () -> Hashtbl.mem canceled req_key)
                         lsp_cfg ~on_outputs_ready ~on_goals_ready ~on_goal_done
                     with
                    | Ok out ->
                        if Hashtbl.mem canceled req_key then
                          send_error stdout ~id_json:(Some id) ~code:(-32800) ~message:"Request cancelled"
                        else (
                          if !supports_work_done_progress then
                            send_work_done_end stdout ~token:progress_token ~message:"Done";
                          send_result stdout ~id_json:id
                            ~result_json:(Lsp_protocol.yojson_of_outputs out))
                    | Error msg ->
                        send_error stdout ~id_json:(Some id) ~code:(-32001)
                          ~message:msg)
                | _ -> send_error stdout ~id_json:(Some id) ~code:(-32602) ~message:"Missing valid inputFile")
              id_json
        | Some _ ->
            Option.iter (fun id -> send_error stdout ~id_json:(Some id) ~code:(-32601) ~message:"Method not found") id_json
        | None ->
            Option.iter (fun id -> send_error stdout ~id_json:(Some id) ~code:(-32600) ~message:"Invalid request") id_json)
  done
