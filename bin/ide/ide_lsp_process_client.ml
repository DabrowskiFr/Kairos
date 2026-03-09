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
      (tm.Unix.tm_year + 1900) (tm.Unix.tm_mon + 1) tm.Unix.tm_mday tm.Unix.tm_hour tm.Unix.tm_min tm.Unix.tm_sec who msg;
    close_out_noerr oc)

type t = {
  ic : in_channel;
  oc : out_channel;
  ec : in_channel;
  lock : Mutex.t;
  mutable next_id : int;
  mutable active_request_id : Yojson.Safe.t option;
  mutable closed : bool;
}

let ( |>! ) r f = Result.bind r f

let read_headers ic =
  let rec loop acc =
    let line = input_line ic in
    if line = "" || line = "\r" then List.rev acc else loop (line :: acc)
  in
  loop []

let header_content_length headers =
  List.find_map
    (fun h ->
      let lower = String.lowercase_ascii h in
      if String.length lower >= 15 && String.sub lower 0 15 = "content-length:" then
        Some (int_of_string (String.trim (String.sub h 15 (String.length h - 15))))
      else None)
    headers

let read_message ic =
  try
    let headers = read_headers ic in
    match header_content_length headers with
    | None -> Error "Missing Content-Length"
    | Some len ->
        let body = really_input_string ic len in
        trace_line "lsp-server -> ide-client" body;
        Ok body
  with End_of_file -> Error "LSP server closed stream"

let send_json t (j : Yojson.Safe.t) =
  let body = Yojson.Safe.to_string j in
  trace_line "ide-client -> lsp-server" body;
  output_string t.oc (Printf.sprintf "Content-Length: %d\r\n\r\n%s" (String.length body) body);
  flush t.oc

let send_result t ~(id : Yojson.Safe.t) ~(result_json : Yojson.Safe.t) =
  send_json t (`Assoc [ ("jsonrpc", `String "2.0"); ("id", id); ("result", result_json) ])

let send_error t ~(id : Yojson.Safe.t) ~(code : int) ~(message : string) =
  send_json t
    (`Assoc
      [ ("jsonrpc", `String "2.0");
        ("id", id);
        ("error", `Assoc [ ("code", `Int code); ("message", `String message) ]) ])

let with_lock t f =
  Mutex.lock t.lock;
  Fun.protect ~finally:(fun () -> Mutex.unlock t.lock) f

let member k = function `Assoc xs -> List.assoc_opt k xs | _ -> None
let as_string = function Some (`String s) -> Some s | _ -> None
let id_key = function `Int n -> "i:" ^ string_of_int n | `String s -> "s:" ^ s | `Null -> "n:null" | j -> Yojson.Safe.to_string j

let rec read_json_message t =
  match read_message t.ic with
  | Error e -> Error e
  | Ok s -> ( try Ok (Yojson.Safe.from_string s) with _ -> read_json_message t )

let is_response_for_id j id =
  match member "id" j with
  | Some rid -> id_key rid = id_key (`Int id)
  | None -> false

let error_message_of j =
  member "error" j |> function
  | Some (`Assoc e) -> (match List.assoc_opt "message" e with Some (`String s) -> Some s | _ -> None)
  | _ -> None

let is_server_request (j : Yojson.Safe.t) =
  match (member "method" j, member "id" j, member "result" j, member "error" j) with
  | Some (`String _), Some _, None, None -> true
  | _ -> false

let handle_server_request t (j : Yojson.Safe.t) : unit =
  match (member "method" j, member "id" j) with
  | Some (`String "window/workDoneProgress/create"), Some id ->
      send_result t ~id ~result_json:`Null
  | Some (`String "workspace/configuration"), Some id ->
      send_result t ~id ~result_json:(`List [])
  | Some (`String _), Some id ->
      send_error t ~id ~code:(-32601) ~message:"Method not found"
  | _ -> ()

let call_request_with_notifications t ~(method_name : string) ~(params : Yojson.Safe.t)
    ~(on_notification : Yojson.Safe.t -> unit) : (Yojson.Safe.t, string) result =
  with_lock t (fun () ->
      if t.closed then Error "Process client closed"
      else
        let id = t.next_id in
        t.next_id <- t.next_id + 1;
        t.active_request_id <- Some (`Int id);
        send_json t
          (`Assoc
            [ ("jsonrpc", `String "2.0"); ("id", `Int id); ("method", `String method_name);
              ("params", params) ]);
        let rec loop () =
          match read_json_message t with
          | Error e -> Error e
          | Ok msg when is_response_for_id msg id -> (
              t.active_request_id <- None;
              match error_message_of msg with
              | Some e -> Error e
              | None -> Ok (Option.value (member "result" msg) ~default:`Null))
          | Ok msg when is_server_request msg ->
              handle_server_request t msg;
              loop ()
          | Ok msg ->
              on_notification msg;
              loop ()
        in
        loop ())

let call_request t ~method_name ~params =
  call_request_with_notifications t ~method_name ~params ~on_notification:(fun _ -> ())

let call_notification t ~method_name ~params : (unit, string) result =
  with_lock t (fun () ->
      if t.closed then Error "Process client closed"
      else (
        send_json t
          (`Assoc
            [ ("jsonrpc", `String "2.0"); ("method", `String method_name); ("params", params) ]);
        Ok ()))

let create () =
  let env = Unix.environment () in
  let ic, oc, ec =
    Unix.open_process_args_full "dune" [| "dune"; "exec"; "--"; "kairos-lsp" |] env
  in
  let t =
    { ic; oc; ec; lock = Mutex.create (); next_id = 1; active_request_id = None; closed = false }
  in
  ignore
    (call_request t ~method_name:"initialize"
       ~params:
         (`Assoc
           [
             ("processId", `Null);
             ("rootUri", `Null);
             ("capabilities", `Assoc [ ("window", `Assoc [ ("workDoneProgress", `Bool true) ]) ]);
             ("clientInfo", `Assoc [ ("name", `String "kairos-ide") ]);
           ]));
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

let text_document_position_params ~uri ~line ~character =
  `Assoc
    [
      ("textDocument", `Assoc [ ("uri", `String uri) ]);
      ("position", `Assoc [ ("line", `Int line); ("character", `Int character) ]);
    ]

let extract_hover_text (j : Yojson.Safe.t) : string option =
  match j with
  | `Null -> None
  | `Assoc xs -> (
      match List.assoc_opt "contents" xs with
      | Some (`String s) -> Some s
      | Some (`Assoc c) -> (
          match List.assoc_opt "value" c with
          | Some (`String s) -> Some s
          | _ -> None)
      | Some (`List (`String s :: _)) -> Some s
      | _ -> None)
  | _ -> None

let extract_line_char_from_location (j : Yojson.Safe.t) : (int * int) option =
  let get_start = function
    | `Assoc xs -> (
        match List.assoc_opt "range" xs with
        | Some (`Assoc r) -> (
            match List.assoc_opt "start" r with
            | Some (`Assoc s) -> (
                match (List.assoc_opt "line" s, List.assoc_opt "character" s) with
                | Some (`Int l), Some (`Int c) -> Some (l, c)
                | _ -> None)
            | _ -> None)
        | _ -> None)
    | _ -> None
  in
  match j with
  | `Assoc _ -> get_start j
  | `List (x :: _) -> get_start x
  | _ -> None

let extract_references (j : Yojson.Safe.t) : (int * int) list =
  match j with
  | `List xs ->
      List.filter_map
        (fun x ->
          match extract_line_char_from_location x with Some lc -> Some lc | None -> None)
        xs
  | _ -> []

let extract_completion_labels (j : Yojson.Safe.t) : string list =
  let items =
    match j with
    | `List xs -> xs
    | `Assoc xs -> (
        match List.assoc_opt "items" xs with Some (`List ys) -> ys | _ -> [])
    | _ -> []
  in
  items
  |> List.filter_map (function `Assoc kv -> (match List.assoc_opt "label" kv with Some (`String s) -> Some s | _ -> None) | _ -> None)

let parse_outline_sections (j : Yojson.Safe.t) : (Ide_lsp_types.outline_sections, string) result =
  let parse_name_line = function
    | `Assoc kv -> (
        match (List.assoc_opt "name" kv, List.assoc_opt "line" kv) with
        | Some (`String name), Some (`Int line) -> Ok (name, line)
        | _ -> Error "Invalid outline entry")
    | _ -> Error "Invalid outline entry"
  in
  let parse_list = function
    | `List xs ->
        List.fold_right
          (fun x acc ->
            acc |>! fun acc ->
            parse_name_line x |>! fun e -> Ok (e :: acc))
          xs (Ok [])
    | _ -> Error "Invalid outline list"
  in
  match j with
  | `Assoc kv ->
      let open Ide_lsp_types in
      (match (List.assoc_opt "nodes" kv, List.assoc_opt "transitions" kv, List.assoc_opt "contracts" kv) with
      | Some n, Some t, Some c ->
          parse_list n |>! fun nodes ->
          parse_list t |>! fun transitions ->
          parse_list c |>! fun contracts ->
          Ok { Ide_lsp_types.nodes = nodes; transitions; contracts }
      | _ -> Error "Invalid outline sections")
  | _ -> Error "Invalid outline sections"

let parse_goal_tree (j : Yojson.Safe.t) : (Ide_lsp_types.goal_tree_node list, string) result =
  let open Ide_lsp_types in
  let parse_entry = function
    | `Assoc kv ->
        let pick_int k = match List.assoc_opt k kv with Some (`Int i) -> Ok i | _ -> Error ("Missing int " ^ k) in
        let pick_float k = match List.assoc_opt k kv with Some (`Float f) -> Ok f | Some (`Int i) -> Ok (float_of_int i) | _ -> Error ("Missing float " ^ k) in
        let pick_string k = match List.assoc_opt k kv with Some (`String s) -> Ok s | _ -> Error ("Missing string " ^ k) in
        let pick_opt_string k = match List.assoc_opt k kv with Some (`String s) -> Ok (Some s) | Some `Null | None -> Ok None | _ -> Error ("Invalid optional string " ^ k) in
        pick_int "idx" |>! fun idx ->
        pick_int "display_no" |>! fun display_no ->
        pick_string "goal" |>! fun goal ->
        pick_string "status" |>! fun status ->
        pick_float "time_s" |>! fun time_s ->
        pick_opt_string "dump_path" |>! fun dump_path ->
        pick_string "source" |>! fun source ->
        pick_opt_string "vcid" |>! fun vcid ->
        Ok
          {
            Ide_lsp_types.idx = idx;
            display_no;
            goal;
            status;
            time_s;
            dump_path;
            source;
            vcid;
          }
    | _ -> Error "Invalid goal tree entry"
  in
  let parse_entries = function
    | `List xs ->
        List.fold_right
          (fun x acc -> acc |>! fun acc -> parse_entry x |>! fun e -> Ok (e :: acc))
          xs (Ok [])
    | _ -> Error "Invalid goal tree items"
  in
  let parse_transition = function
    | `Assoc kv ->
        let pick_int k = match List.assoc_opt k kv with Some (`Int i) -> Ok i | _ -> Error ("Missing int " ^ k) in
        let pick_string k = match List.assoc_opt k kv with Some (`String s) -> Ok s | _ -> Error ("Missing string " ^ k) in
        pick_string "transition" |>! fun transition ->
        pick_string "source" |>! fun source ->
        pick_int "succeeded" |>! fun succeeded ->
        pick_int "total" |>! fun total ->
        (match List.assoc_opt "items" kv with
        | Some items ->
            parse_entries items |>! fun items ->
            Ok
              {
                Ide_lsp_types.transition = transition;
                source;
                succeeded;
                total;
                items;
              }
        | None -> Error "Missing items")
    | _ -> Error "Invalid goal tree transition"
  in
  let parse_transitions = function
    | `List xs ->
        List.fold_right
          (fun x acc -> acc |>! fun acc -> parse_transition x |>! fun t -> Ok (t :: acc))
          xs (Ok [])
    | _ -> Error "Invalid goal tree transitions"
  in
  let parse_node = function
    | `Assoc kv ->
        let pick_int k = match List.assoc_opt k kv with Some (`Int i) -> Ok i | _ -> Error ("Missing int " ^ k) in
        let pick_string k = match List.assoc_opt k kv with Some (`String s) -> Ok s | _ -> Error ("Missing string " ^ k) in
        pick_string "node" |>! fun node ->
        pick_string "source" |>! fun source ->
        pick_int "succeeded" |>! fun succeeded ->
        pick_int "total" |>! fun total ->
        (match List.assoc_opt "transitions" kv with
        | Some transitions ->
            parse_transitions transitions |>! fun transitions ->
            Ok
              {
                Ide_lsp_types.node = node;
                source;
                succeeded;
                total;
                transitions;
              }
        | None -> Error "Missing transitions")
    | _ -> Error "Invalid goal tree node"
  in
  match j with
  | `List xs ->
      List.fold_right
        (fun x acc -> acc |>! fun acc -> parse_node x |>! fun n -> Ok (n :: acc))
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
      (`Assoc
        [
          ("textDocument", `Assoc [ ("uri", `String uri) ]);
          ("position", `Assoc [ ("line", `Int line); ("character", `Int character) ]);
          ("context", `Assoc [ ("includeDeclaration", `Bool true) ]);
        ])
  |>! fun j -> Ok (extract_references j)

let completion t ~uri ~line ~character =
  call_request t ~method_name:"textDocument/completion"
    ~params:(text_document_position_params ~uri ~line ~character)
  |>! fun j -> Ok (extract_completion_labels j)

let formatting t ~uri =
  call_request t ~method_name:"textDocument/formatting"
    ~params:
      (`Assoc
        [
          ("textDocument", `Assoc [ ("uri", `String uri) ]);
          ("options", `Assoc [ ("tabSize", `Int 2); ("insertSpaces", `Bool true) ]);
        ])
  |>! fun j ->
  match j with
  | `List (`Assoc e :: _) -> (
      match List.assoc_opt "newText" e with Some (`String s) -> Ok (Some s) | _ -> Ok None)
  | `List [] -> Ok None
  | _ -> Ok None

let outline t ~uri ~abstract_text =
  call_request t ~method_name:"kairos/outline"
    ~params:(`Assoc [ ("uri", `String uri); ("abstractText", `String abstract_text) ])
  |>! fun j ->
  match j with
  | `Assoc kv -> (
      match (List.assoc_opt "source" kv, List.assoc_opt "abstract" kv) with
      | Some source_j, Some abstract_j ->
          parse_outline_sections source_j |>! fun source ->
          parse_outline_sections abstract_j |>! fun abstract_program ->
          Ok { Ide_lsp_types.source; abstract_program }
      | _ -> Error "Invalid outline payload")
  | _ -> Error "Invalid outline payload"

let goals_tree_final t ~goals ~vc_sources ~vc_text =
  call_request t ~method_name:"kairos/goalsTreeFinal"
    ~params:
      (`Assoc
        [
          ("goals", `List (List.map Lsp_protocol.yojson_of_goal_info goals));
          ("vcSources", `List (List.map (fun (k, v) -> `List [ `Int k; `String v ]) vc_sources));
          ("vcText", `String vc_text);
        ])
  |>! parse_goal_tree

let goals_tree_pending t ~goal_names ~vc_ids ~vc_sources =
  call_request t ~method_name:"kairos/goalsTreePending"
    ~params:
      (`Assoc
        [
          ("goalNames", `List (List.map (fun s -> `String s) goal_names));
          ("vcIds", `List (List.map (fun i -> `Int i) vc_ids));
          ("vcSources", `List (List.map (fun (k, v) -> `List [ `Int k; `String v ]) vc_sources));
        ])
  |>! parse_goal_tree

let cancel_active_request t =
  match t.active_request_id with
  | None -> Ok ()
  | Some id ->
      call_notification t ~method_name:"$/cancelRequest"
        ~params:(`Assoc [ ("id", id) ])

let did_open t ~uri ~text =
  call_notification t ~method_name:"textDocument/didOpen"
    ~params:
      (`Assoc
        [
          ("textDocument",
           `Assoc
             [
               ("uri", `String uri);
               ("languageId", `String "kairos");
               ("version", `Int 1);
               ("text", `String text);
             ]);
        ])

let did_change t ~uri ~version ~text =
  call_notification t ~method_name:"textDocument/didChange"
    ~params:
      (`Assoc
        [
          ("textDocument", `Assoc [ ("uri", `String uri); ("version", `Int version) ]);
          ("contentChanges", `List [ `Assoc [ ("text", `String text) ] ]);
        ])

let did_save t ~uri =
  call_notification t ~method_name:"textDocument/didSave"
    ~params:(`Assoc [ ("textDocument", `Assoc [ ("uri", `String uri) ]) ])

let did_close t ~uri =
  call_notification t ~method_name:"textDocument/didClose"
    ~params:(`Assoc [ ("textDocument", `Assoc [ ("uri", `String uri) ]) ])

let default_engine () =
  match Option.map String.lowercase_ascii (Sys.getenv_opt "KAIROS_IDE_ENGINE") with
  | Some "v2" -> "v2"
  | _ -> "v2"

let instrumentation_pass t ~generate_png ~input_file =
  call_request t ~method_name:"kairos/instrumentationPass"
    ~params:
      (`Assoc
        [
          ("inputFile", `String input_file);
          ("generatePng", `Bool generate_png);
          ("engine", `String (default_engine ()));
        ])
  |>!  Lsp_protocol.automata_outputs_of_yojson

let obc_pass t ~input_file =
  call_request t ~method_name:"kairos/obcPass"
    ~params:(`Assoc [ ("inputFile", `String input_file); ("engine", `String (default_engine ())) ])
  |>!  Lsp_protocol.obc_outputs_of_yojson

let why_pass t ~prefix_fields ~input_file =
  call_request t ~method_name:"kairos/whyPass"
    ~params:
      (`Assoc
        [
          ("inputFile", `String input_file);
          ("prefixFields", `Bool prefix_fields);
          ("engine", `String (default_engine ()));
        ])
  |>!  Lsp_protocol.why_outputs_of_yojson

let obligations_pass t ~prefix_fields ~prover ~input_file =
  call_request t ~method_name:"kairos/obligationsPass"
    ~params:
      (`Assoc
        [
          ("inputFile", `String input_file);
          ("prover", `String prover);
          ("prefixFields", `Bool prefix_fields);
          ("engine", `String (default_engine ()));
        ])
  |>!  Lsp_protocol.obligations_outputs_of_yojson

let eval_pass t ~input_file ~trace_text ~with_state ~with_locals =
  call_request t ~method_name:"kairos/evalPass"
    ~params:
      (`Assoc
        [
          ("inputFile", `String input_file);
          ("traceText", `String trace_text);
          ("withState", `Bool with_state);
          ("withLocals", `Bool with_locals);
          ("engine", `String (default_engine ()));
        ])
  |>!  (function `String s -> Ok s | _ -> Error "Invalid evalPass response")

let dot_png_from_text t ~dot_text =
  call_request t ~method_name:"kairos/dotPngFromText"
    ~params:(`Assoc [ ("dotText", `String dot_text) ])
  |>!  (function `Null -> Ok None | `String s -> Ok (Some s) | _ -> Error "Invalid dotPngFromText response")

let run t (cfg : Ide_lsp_types.config) =
  call_request t ~method_name:"kairos/run"
    ~params:(
      `Assoc
        [ ("inputFile", `String cfg.Ide_lsp_types.input_file); ("prover", `String cfg.Ide_lsp_types.prover);
          ("engine", `String cfg.Ide_lsp_types.engine);
          ("proverCmd", match cfg.Ide_lsp_types.prover_cmd with None -> `Null | Some s -> `String s);
          ("wpOnly", `Bool cfg.Ide_lsp_types.wp_only); ("smokeTests", `Bool cfg.Ide_lsp_types.smoke_tests);
          ("timeoutS", `Int cfg.Ide_lsp_types.timeout_s); ("prefixFields", `Bool cfg.Ide_lsp_types.prefix_fields);
          ("prove", `Bool cfg.Ide_lsp_types.prove); ("generateVcText", `Bool cfg.Ide_lsp_types.generate_vc_text);
          ("generateSmtText", `Bool cfg.Ide_lsp_types.generate_smt_text);
          ("generateMonitorText", `Bool cfg.Ide_lsp_types.generate_monitor_text);
          ("generateDotPng", `Bool cfg.Ide_lsp_types.generate_dot_png) ])
  |>!  Lsp_protocol.outputs_of_yojson

let run_with_callbacks t (cfg : Ide_lsp_types.config) ~on_outputs_ready ~on_goals_ready ~on_goal_done =
  let on_notification msg =
    match as_string (member "method" msg) with
    | Some "kairos/goalsReady" -> (
        match member "params" msg |> function Some (`Assoc ps) -> List.assoc_opt "payload" ps | _ -> None with
        | Some (`Assoc p) -> (
            let names =
              match List.assoc_opt "names" p with
              | Some (`List xs) -> List.filter_map (function `String s -> Some s | _ -> None) xs
              | _ -> []
            in
            let vc_ids =
              match List.assoc_opt "vcIds" p with
              | Some (`List xs) -> List.filter_map (function `Int i -> Some i | _ -> None) xs
              | _ -> []
            in
            on_goals_ready (names, vc_ids))
        | _ -> ())
    | Some "kairos/goalDone" -> (
        match member "params" msg |> function Some (`Assoc ps) -> List.assoc_opt "payload" ps | _ -> None with
        | Some (`Assoc p) ->
            let idx = match List.assoc_opt "idx" p with Some (`Int i) -> i | _ -> -1 in
            let goal = match List.assoc_opt "goal" p with Some (`String s) -> s | _ -> "" in
            let status = match List.assoc_opt "status" p with Some (`String s) -> s | _ -> "" in
            let time_s = match List.assoc_opt "time_s" p with Some (`Float f) -> f | Some (`Int i) -> float_of_int i | _ -> 0.0 in
            let dump_path = match List.assoc_opt "dump_path" p with Some (`String s) -> Some s | _ -> None in
            let source = match List.assoc_opt "source" p with Some (`String s) -> s | _ -> "" in
            let vcid = match List.assoc_opt "vcid" p with Some (`String s) -> Some s | _ -> None in
            on_goal_done idx goal status time_s dump_path source vcid
        | _ -> ())
    | Some "kairos/outputsReady" -> (
        match member "params" msg |> function Some (`Assoc ps) -> List.assoc_opt "payload" ps | _ -> None with
        | Some payload -> (
            match Lsp_protocol.outputs_of_yojson payload with Ok out -> on_outputs_ready out | Error _ -> ())
        | None -> ())
    | _ -> ()
  in
  call_request_with_notifications t ~method_name:"kairos/run"
    ~params:(
      `Assoc
        [ ("inputFile", `String cfg.Ide_lsp_types.input_file); ("prover", `String cfg.Ide_lsp_types.prover);
          ("engine", `String cfg.Ide_lsp_types.engine);
          ("proverCmd", match cfg.Ide_lsp_types.prover_cmd with None -> `Null | Some s -> `String s);
          ("wpOnly", `Bool cfg.Ide_lsp_types.wp_only); ("smokeTests", `Bool cfg.Ide_lsp_types.smoke_tests);
          ("timeoutS", `Int cfg.Ide_lsp_types.timeout_s); ("prefixFields", `Bool cfg.Ide_lsp_types.prefix_fields);
          ("prove", `Bool cfg.Ide_lsp_types.prove); ("generateVcText", `Bool cfg.Ide_lsp_types.generate_vc_text);
          ("generateSmtText", `Bool cfg.Ide_lsp_types.generate_smt_text);
          ("generateMonitorText", `Bool cfg.Ide_lsp_types.generate_monitor_text);
          ("generateDotPng", `Bool cfg.Ide_lsp_types.generate_dot_png) ])
    ~on_notification
  |>!  Lsp_protocol.outputs_of_yojson
