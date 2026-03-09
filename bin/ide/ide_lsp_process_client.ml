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
      (tm.Unix.tm_year + 1900) (tm.Unix.tm_mon + 1) tm.Unix.tm_mday tm.Unix.tm_hour tm.Unix.tm_min tm.Unix.tm_sec who msg;
    close_out_noerr oc)

type t = {
  ic : in_channel;
  oc : out_channel;
  ec : in_channel;
  lock : Mutex.t;
  mutable next_id : int;
  mutable active_request_id : Jsonrpc.Id.t option;
  mutable closed : bool;
}

let ( |>! ) r f = Result.bind r f

let send_packet t (packet : Jsonrpc.Packet.t) =
  trace_line "ide-client -> lsp-server" (Jsonrpc.Packet.yojson_of_t packet |> Yojson.Safe.to_string);
  Transport.write t.oc packet

let send_result t ~(id : Jsonrpc.Id.t) ~(result_json : Yojson.Safe.t) =
  send_packet t (Jsonrpc.Packet.Response (Jsonrpc.Response.ok id result_json))

let send_error t ~(id : Jsonrpc.Id.t) ~(code : int) ~(message : string) =
  let code =
    match code with
    | -32700 -> Jsonrpc.Response.Error.Code.ParseError
    | -32600 -> Jsonrpc.Response.Error.Code.InvalidRequest
    | -32601 -> Jsonrpc.Response.Error.Code.MethodNotFound
    | -32602 -> Jsonrpc.Response.Error.Code.InvalidParams
    | -32603 -> Jsonrpc.Response.Error.Code.InternalError
    | -32002 -> Jsonrpc.Response.Error.Code.ServerNotInitialized
    | -32800 -> Jsonrpc.Response.Error.Code.RequestCancelled
    | n -> Jsonrpc.Response.Error.Code.Other n
  in
  let error = Jsonrpc.Response.Error.make ~code ~message () in
  send_packet t (Jsonrpc.Packet.Response (Jsonrpc.Response.error id error))

let with_lock t f =
  Mutex.lock t.lock;
  Fun.protect ~finally:(fun () -> Mutex.unlock t.lock) f

let id_key (id : Jsonrpc.Id.t) = Jsonrpc.Id.yojson_of_t id |> Yojson.Safe.to_string

let rec read_packet t =
  try
    match Transport.read t.ic with
    | Some packet ->
        trace_line "lsp-server -> ide-client" (Jsonrpc.Packet.yojson_of_t packet |> Yojson.Safe.to_string);
        Ok packet
    | None -> Error "LSP server closed stream"
  with _ -> read_packet t

let structured_params = function
  | (`Assoc _ | `List _) as json -> Some (Jsonrpc.Structured.t_of_yojson json)
  | _ -> None

let handle_server_request t (request : Jsonrpc.Request.t) : unit =
  match request.method_ with
  | "window/workDoneProgress/create" ->
      send_result t ~id:request.id ~result_json:`Null
  | "workspace/configuration" ->
      send_result t ~id:request.id ~result_json:(`List [])
  | _ ->
      send_error t ~id:request.id ~code:(-32601) ~message:"Method not found"

let call_request_with_notifications t ~(method_name : string) ~(params : Yojson.Safe.t)
    ~(on_notification : Jsonrpc.Notification.t -> unit) : (Yojson.Safe.t, string) result =
  with_lock t (fun () ->
      if t.closed then Error "Process client closed"
      else
        let id : Jsonrpc.Id.t = `Int t.next_id in
        t.next_id <- t.next_id + 1;
        t.active_request_id <- Some id;
        let params = structured_params params in
        send_packet t (Jsonrpc.Packet.Request (Jsonrpc.Request.create ?params ~id ~method_:method_name ()));
        let rec loop () =
          match read_packet t with
          | Error e -> Error e
          | Ok (Jsonrpc.Packet.Response response) when id_key response.id = id_key id -> (
              t.active_request_id <- None;
              match response.result with
              | Ok result -> Ok result
              | Error error -> Error error.message)
          | Ok (Jsonrpc.Packet.Request request) ->
              handle_server_request t request;
              loop ()
          | Ok (Jsonrpc.Packet.Notification notif) ->
              on_notification notif;
              loop ()
          | Ok _ ->
              loop ()
        in
        loop ())

let call_request t ~method_name ~params =
  call_request_with_notifications t ~method_name ~params ~on_notification:(fun _ -> ())

let call_notification t ~method_name ~params : (unit, string) result =
  with_lock t (fun () ->
      if t.closed then Error "Process client closed"
      else (
        let params = structured_params params in
        send_packet t (Jsonrpc.Packet.Notification (Jsonrpc.Notification.create ?params ~method_:method_name ()));
        Ok ()))

let create () =
  let env = Unix.environment () in
  let ic, oc, ec =
    Unix.open_process_args_full "dune" [| "dune"; "exec"; "--"; "kairos-lsp" |] env
  in
  let t =
    { ic; oc; ec; lock = Mutex.create (); next_id = 1; active_request_id = None; closed = false }
  in
  let capabilities =
    let window = Lsp_types.WindowClientCapabilities.create ~workDoneProgress:true () in
    Lsp_types.ClientCapabilities.create ~window ()
  in
  ignore
    (call_request t ~method_name:"initialize"
       ~params:
         (Lsp_types.InitializeParams.create ~capabilities
            ~clientInfo:(Lsp_types.InitializeParams.create_clientInfo ~name:"kairos-ide" ()) ()
         |> Lsp_types.InitializeParams.yojson_of_t));
  ignore (call_notification t ~method_name:"initialized" ~params:(`Assoc []));
  t

let close t =
  if not t.closed then (
    ignore (call_request t ~method_name:"shutdown" ~params:`Null);
    ignore (call_notification t ~method_name:"exit" ~params:`Null);
    with_lock t (fun () -> t.closed <- true);
    close_out_noerr t.oc;
    close_in_noerr t.ic;
    close_in_noerr t.ec)

let lsp_position ~line ~character = Lsp_types.Position.create ~line ~character

let text_document_identifier ~uri =
  Lsp_types.TextDocumentIdentifier.create ~uri:(Lsp_types.DocumentUri.of_string uri)

let text_document_position_params ~uri ~line ~character =
  Lsp_types.HoverParams.create ~textDocument:(text_document_identifier ~uri)
    ~position:(lsp_position ~line ~character) ()
  |> Lsp_types.HoverParams.yojson_of_t

let extract_hover_text (j : Yojson.Safe.t) : string option =
  if j = `Null then None
  else
    try
      match Lsp_types.Hover.t_of_yojson j with
      | { contents = `MarkupContent c; _ } -> Some c.value
      | { contents = `MarkedString ms; _ } -> Some ms.value
      | { contents = `List (ms :: _); _ } -> Some ms.value
      | _ -> None
    with _ -> None

let line_char_of_location (loc : Lsp_types.Location.t) : int * int =
  (loc.range.start.line, loc.range.start.character)

let first_location_of_json (j : Yojson.Safe.t) : Lsp_types.Location.t option =
  try
    if j = `Null then None
    else
      match j with
      | `List (x :: _) -> Some (Lsp_types.Location.t_of_yojson x)
      | _ -> Some (Lsp_types.Location.t_of_yojson j)
  with _ -> None

let extract_line_char_from_location (j : Yojson.Safe.t) : (int * int) option =
  Option.map line_char_of_location (first_location_of_json j)

let extract_references (j : Yojson.Safe.t) : (int * int) list =
  try
    match j with
    | `List xs ->
        List.filter_map
          (fun x ->
            try
              Some (line_char_of_location (Lsp_types.Location.t_of_yojson x))
            with _ -> None)
          xs
    | _ -> []
  with _ -> []

let extract_completion_labels (j : Yojson.Safe.t) : string list =
  try
    match j with
    | `List xs ->
        List.filter_map (fun x -> try Some (Lsp_types.CompletionItem.t_of_yojson x).label with _ -> None) xs
    | _ ->
        let list = Lsp_types.CompletionList.t_of_yojson j in
        List.map (fun item -> item.Lsp_types.CompletionItem.label) list.items
  with _ -> []

let first_text_edit_new_text (j : Yojson.Safe.t) : string option =
  try
    match j with
    | `List (edit_json :: _) -> Some (Lsp_types.TextEdit.t_of_yojson edit_json).newText
    | `List [] -> None
    | _ -> None
  with _ -> None

let ide_outline_sections_of_protocol (s : Lsp_protocol.outline_sections) : Ide_lsp_types.outline_sections =
  { Ide_lsp_types.nodes = s.nodes; transitions = s.transitions; contracts = s.contracts }

let ide_outline_payload_of_protocol (p : Lsp_protocol.outline_payload) : Ide_lsp_types.outline_payload =
  {
    Ide_lsp_types.source = ide_outline_sections_of_protocol p.source;
    abstract_program = ide_outline_sections_of_protocol p.abstract_program;
  }

let rec ide_goal_tree_entry_of_protocol (e : Lsp_protocol.goal_tree_entry) : Ide_lsp_types.goal_tree_entry =
  {
    Ide_lsp_types.idx = e.idx;
    display_no = e.display_no;
    goal = e.goal;
    status = e.status;
    time_s = e.time_s;
    dump_path = e.dump_path;
    source = e.source;
    vcid = e.vcid;
  }

and ide_goal_tree_transition_of_protocol
    (t : Lsp_protocol.goal_tree_transition) : Ide_lsp_types.goal_tree_transition =
  {
    Ide_lsp_types.transition = t.transition;
    source = t.source;
    succeeded = t.succeeded;
    total = t.total;
    items = List.map ide_goal_tree_entry_of_protocol t.items;
  }

and ide_goal_tree_node_of_protocol (n : Lsp_protocol.goal_tree_node) : Ide_lsp_types.goal_tree_node =
  {
    Ide_lsp_types.node = n.node;
    source = n.source;
    succeeded = n.succeeded;
    total = n.total;
    transitions = List.map ide_goal_tree_transition_of_protocol n.transitions;
  }

let parse_outline_payload (j : Yojson.Safe.t) : (Ide_lsp_types.outline_payload, string) result =
  Lsp_protocol.outline_payload_of_yojson j |> Result.map ide_outline_payload_of_protocol

let parse_goal_tree (j : Yojson.Safe.t) : (Ide_lsp_types.goal_tree_node list, string) result =
  match j with
  | `List xs ->
      List.fold_right
        (fun x acc ->
          acc |>! fun acc ->
          Lsp_protocol.goal_tree_node_of_yojson x |> Result.map ide_goal_tree_node_of_protocol
          |>! fun node -> Ok (node :: acc))
        xs (Ok [])
  | _ -> Error "Invalid goal tree payload"

let hover t ~uri ~line ~character =
  call_request t ~method_name:"textDocument/hover"
    ~params:(text_document_position_params ~uri ~line ~character)
  |>! fun j -> Ok (extract_hover_text j)

let definition t ~uri ~line ~character =
  call_request t ~method_name:"textDocument/definition"
    ~params:(text_document_position_params ~uri ~line ~character)
  |>! fun j ->
  match extract_line_char_from_location j with
  | Some lc -> Ok lc
  | None -> Error "No definition found"

let references t ~uri ~line ~character =
  call_request t ~method_name:"textDocument/references"
    ~params:
      (Lsp_types.ReferenceParams.create
         ~textDocument:(text_document_identifier ~uri)
         ~position:(lsp_position ~line ~character)
         ~context:(Lsp_types.ReferenceContext.create ~includeDeclaration:true) ()
      |> Lsp_types.ReferenceParams.yojson_of_t)
  |>! fun j -> Ok (extract_references j)

let completion t ~uri ~line ~character =
  call_request t ~method_name:"textDocument/completion"
    ~params:
      (Lsp_types.CompletionParams.create ~textDocument:(text_document_identifier ~uri)
         ~position:(lsp_position ~line ~character) ()
      |> Lsp_types.CompletionParams.yojson_of_t)
  |>! fun j -> Ok (extract_completion_labels j)

let formatting t ~uri =
  call_request t ~method_name:"textDocument/formatting"
    ~params:
      (Lsp_types.DocumentFormattingParams.create ~textDocument:(text_document_identifier ~uri)
         ~options:(Lsp_types.FormattingOptions.create ~tabSize:2 ~insertSpaces:true ()) ()
      |> Lsp_types.DocumentFormattingParams.yojson_of_t)
  |>! fun j -> Ok (first_text_edit_new_text j)

let outline t ~uri ~abstract_text =
  call_request t ~method_name:"kairos/outline"
    ~params:
      (Lsp_protocol.yojson_of_outline_request
         { uri = Some uri; source_text = None; abstract_text = Some abstract_text })
  |>! parse_outline_payload

let goals_tree_final t ~goals ~vc_sources ~vc_text =
  call_request t ~method_name:"kairos/goalsTreeFinal"
    ~params:
      (Lsp_protocol.yojson_of_goals_tree_final_request
         { goals; vc_sources; vc_text })
  |>! parse_goal_tree

let goals_tree_pending t ~goal_names ~vc_ids ~vc_sources =
  call_request t ~method_name:"kairos/goalsTreePending"
    ~params:
      (Lsp_protocol.yojson_of_goals_tree_pending_request
         { goal_names; vc_ids; vc_sources })
  |>! parse_goal_tree

let cancel_active_request t =
  match t.active_request_id with
  | None -> Ok ()
  | Some id ->
      call_notification t ~method_name:"$/cancelRequest"
        ~params:(Lsp_types.CancelParams.create ~id |> Lsp_types.CancelParams.yojson_of_t)

let did_open t ~uri ~text =
  call_notification t ~method_name:"textDocument/didOpen"
    ~params:
      (Lsp_types.DidOpenTextDocumentParams.create
         ~textDocument:
           (Lsp_types.TextDocumentItem.create ~uri:(Lsp_types.DocumentUri.of_string uri)
              ~languageId:"kairos" ~version:1 ~text)
      |> Lsp_types.DidOpenTextDocumentParams.yojson_of_t)

let did_change t ~uri ~version ~text =
  call_notification t ~method_name:"textDocument/didChange"
    ~params:
      (Lsp_types.DidChangeTextDocumentParams.create
         ~textDocument:
           (Lsp_types.VersionedTextDocumentIdentifier.create ~uri:(Lsp_types.DocumentUri.of_string uri)
              ~version)
         ~contentChanges:[ Lsp_types.TextDocumentContentChangeEvent.create ~text () ]
      |> Lsp_types.DidChangeTextDocumentParams.yojson_of_t)

let did_save t ~uri =
  call_notification t ~method_name:"textDocument/didSave"
    ~params:
      (Lsp_types.DidSaveTextDocumentParams.create ~textDocument:(text_document_identifier ~uri) ()
      |> Lsp_types.DidSaveTextDocumentParams.yojson_of_t)

let did_close t ~uri =
  call_notification t ~method_name:"textDocument/didClose"
    ~params:
      (Lsp_types.DidCloseTextDocumentParams.create ~textDocument:(text_document_identifier ~uri)
      |> Lsp_types.DidCloseTextDocumentParams.yojson_of_t)

let default_engine () =
  match Option.map String.lowercase_ascii (Sys.getenv_opt "KAIROS_IDE_ENGINE") with
  | Some "v2" -> "v2"
  | _ -> "v2"

let instrumentation_pass t ~generate_png ~input_file =
  call_request t ~method_name:"kairos/instrumentationPass"
    ~params:
      (Lsp_protocol.yojson_of_instrumentation_pass_request
         { input_file; generate_png; engine = default_engine () })
  |>!  Lsp_protocol.automata_outputs_of_yojson

let obc_pass t ~input_file =
  call_request t ~method_name:"kairos/obcPass"
    ~params:(Lsp_protocol.yojson_of_obc_pass_request { input_file; engine = default_engine () })
  |>!  Lsp_protocol.obc_outputs_of_yojson

let why_pass t ~prefix_fields ~input_file =
  call_request t ~method_name:"kairos/whyPass"
    ~params:(Lsp_protocol.yojson_of_why_pass_request { input_file; prefix_fields; engine = default_engine () })
  |>!  Lsp_protocol.why_outputs_of_yojson

let obligations_pass t ~prefix_fields ~prover ~input_file =
  call_request t ~method_name:"kairos/obligationsPass"
    ~params:
      (Lsp_protocol.yojson_of_obligations_pass_request
         { input_file; prover; prefix_fields; engine = default_engine () })
  |>!  Lsp_protocol.obligations_outputs_of_yojson

let eval_pass t ~input_file ~trace_text ~with_state ~with_locals =
  call_request t ~method_name:"kairos/evalPass"
    ~params:
      (Lsp_protocol.yojson_of_eval_pass_request
         { input_file; trace_text; with_state; with_locals; engine = default_engine () })
  |>!  (function `String s -> Ok s | _ -> Error "Invalid evalPass response")

let dot_png_from_text t ~dot_text =
  call_request t ~method_name:"kairos/dotPngFromText"
    ~params:(Lsp_protocol.yojson_of_dot_png_from_text_request { dot_text })
  |>!  (function `Null -> Ok None | `String s -> Ok (Some s) | _ -> Error "Invalid dotPngFromText response")

let run t (cfg : Ide_lsp_types.config) =
  call_request t ~method_name:"kairos/run"
    ~params:(Lsp_protocol.yojson_of_config cfg)
  |>!  Lsp_protocol.outputs_of_yojson

let decode_notification_params notif decode =
  match notif.Jsonrpc.Notification.params with
  | Some params -> decode (params :> Yojson.Safe.t)
  | None -> Error "Missing notification params"

let run_with_callbacks t (cfg : Ide_lsp_types.config) ~on_outputs_ready ~on_goals_ready ~on_goal_done =
  let on_notification notif =
    match notif.Jsonrpc.Notification.method_ with
    | "kairos/goalsReady" -> (
        match decode_notification_params notif Lsp_protocol.goals_ready_notification_of_yojson with
        | Ok notification -> on_goals_ready (notification.payload.names, notification.payload.vc_ids)
        | Error _ -> ())
    | "kairos/goalDone" -> (
        match decode_notification_params notif Lsp_protocol.goal_done_notification_of_yojson with
        | Ok notification ->
            let payload = notification.payload in
            on_goal_done payload.idx payload.goal payload.status payload.time_s payload.dump_path
              payload.source payload.vcid
        | Error _ -> ())
    | "kairos/outputsReady" -> (
        match decode_notification_params notif Lsp_protocol.outputs_ready_notification_of_yojson with
        | Ok notification -> on_outputs_ready notification.payload
        | Error _ -> ())
    | _ -> ()
  in
  call_request_with_notifications t ~method_name:"kairos/run"
    ~params:(Lsp_protocol.yojson_of_config cfg)
    ~on_notification
  |>!  Lsp_protocol.outputs_of_yojson
