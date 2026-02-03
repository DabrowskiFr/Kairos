type level = Quiet | Normal | Verbose | Debug | Trace

type format = Pretty | Json

type color = Auto | Always | Never

type relevance = Low | Medium | High

type event_kind =
  | StageStart
  | StageEnd
  | StageInfo
  | OutputWritten
  | Warning
  | Error

type event = {
  kind : event_kind;
  stage : Stage_names.stage_id option;
  level : level;
  relevance : relevance;
  message : string;
  data : (string * string) list;
  duration_ms : int option;
}

type config = {
  level : level;
  format : format;
  color : color;
  output : out_channel;
}

let default_config = {
  level = Normal;
  format = Pretty;
  color = Auto;
  output = stderr;
}

let current_config = ref default_config

let set_config cfg = current_config := cfg
let get_config () = !current_config

let parse_level = function
  | "quiet" -> Ok Quiet
  | "normal" -> Ok Normal
  | "verbose" -> Ok Verbose
  | "debug" -> Ok Debug
  | "trace" -> Ok Trace
  | other -> Error ("Unknown log level: " ^ other)

let parse_format = function
  | "pretty" -> Ok Pretty
  | "json" -> Ok Json
  | other -> Error ("Unknown log format: " ^ other)

let parse_color = function
  | "auto" -> Ok Auto
  | "always" -> Ok Always
  | "never" -> Ok Never
  | other -> Error ("Unknown log color: " ^ other)

let level_rank = function
  | Quiet -> 0
  | Normal -> 1
  | Verbose -> 2
  | Debug -> 3
  | Trace -> 4

let relevance_rank = function
  | Low -> 0
  | Medium -> 1
  | High -> 2

let should_emit (cfg:config) (event:event) =
  level_rank event.level <= level_rank cfg.level
  && relevance_rank event.relevance >= 0

let supports_color cfg =
  match cfg.color with
  | Always -> true
  | Never -> false
  | Auto ->
      let oc = cfg.output in
      Unix.isatty (Unix.descr_of_out_channel oc)

let color_code = function
  | StageStart | StageEnd -> "\027[36m"
  | StageInfo -> "\027[34m"
  | OutputWritten -> "\027[32m"
  | Warning -> "\027[33m"
  | Error -> "\027[31m"

let reset_code = "\027[0m"

let pp_event_pretty cfg event =
  let stage =
    match event.stage with
    | None -> ""
    | Some s -> " " ^ Stage_names.to_string s
  in
  let base =
    match event.kind with
    | StageStart -> "[stage]" ^ stage ^ ": start"
    | StageEnd ->
        let dur =
          match event.duration_ms with
          | None -> ""
          | Some ms -> " (" ^ string_of_int ms ^ "ms)"
        in
        "[stage]" ^ stage ^ ": ok" ^ dur
    | StageInfo -> "[info]" ^ stage ^ ": " ^ event.message
    | OutputWritten -> "[output]: " ^ event.message
    | Warning -> "[warn]" ^ stage ^ ": " ^ event.message
    | Error -> "[error]" ^ stage ^ ": " ^ event.message
  in
  let show_data =
    level_rank cfg.level >= level_rank Verbose
    || level_rank event.level >= level_rank Verbose
  in
  let data =
    match event.data, show_data with
    | [], _ -> ""
    | _, false -> ""
    | items, true ->
        let pairs =
          List.map (fun (k, v) -> k ^ ": " ^ v) items
          |> String.concat " | "
        in
        "\n  " ^ pairs
  in
  let line = base ^ data in
  if supports_color cfg then
    color_code event.kind ^ line ^ reset_code
  else
    line

let json_escape s =
  let b = Buffer.create (String.length s) in
  String.iter
    (function
      | '"' -> Buffer.add_string b "\\\""
      | '\\' -> Buffer.add_string b "\\\\"
      | '\n' -> Buffer.add_string b "\\n"
      | '\r' -> Buffer.add_string b "\\r"
      | '\t' -> Buffer.add_string b "\\t"
      | c -> Buffer.add_char b c)
    s;
  Buffer.contents b

let pp_event_json event =
  let stage =
    match event.stage with
    | None -> "null"
    | Some s -> "\"" ^ json_escape (Stage_names.to_string s) ^ "\""
  in
  let data =
    let items =
      List.map
        (fun (k, v) ->
           Printf.sprintf "\"%s\":\"%s\"" (json_escape k) (json_escape v))
        event.data
      |> String.concat ","
    in
    "{" ^ items ^ "}"
  in
  let duration =
    match event.duration_ms with
    | None -> "null"
    | Some ms -> string_of_int ms
  in
  Printf.sprintf
    "{\"kind\":\"%s\",\"stage\":%s,\"message\":\"%s\",\"data\":%s,\"duration_ms\":%s}"
    (match event.kind with
     | StageStart -> "stage_start"
     | StageEnd -> "stage_end"
     | StageInfo -> "stage_info"
     | OutputWritten -> "output_written"
     | Warning -> "warning"
     | Error -> "error")
    stage
    (json_escape event.message)
    data
    duration

let emit event =
  let cfg = get_config () in
  if should_emit cfg event then
    let line =
      match cfg.format with
      | Pretty -> pp_event_pretty cfg event
      | Json -> pp_event_json event
    in
    output_string cfg.output line;
    output_char cfg.output '\n';
    flush cfg.output

let stage_start stage =
  emit {
    kind = StageStart;
    stage = Some stage;
    level = Normal;
    relevance = High;
    message = "start";
    data = [];
    duration_ms = None;
  }

let stage_end stage duration_ms data =
  emit {
    kind = StageEnd;
    stage = Some stage;
    level = Normal;
    relevance = High;
    message = "ok";
    data;
    duration_ms = Some duration_ms;
  }

let stage_info stage message data =
  emit {
    kind = StageInfo;
    stage = Some stage;
    level = Verbose;
    relevance = Medium;
    message;
    data;
    duration_ms = None;
  }

let output_written kind path size =
  emit {
    kind = OutputWritten;
    stage = None;
    level = Normal;
    relevance = Medium;
    message = kind ^ " " ^ path;
    data = ["size", string_of_int size];
    duration_ms = None;
  }

let warning ?stage message =
  emit {
    kind = Warning;
    stage;
    level = Normal;
    relevance = High;
    message;
    data = [];
    duration_ms = None;
  }

let error ?stage message =
  emit {
    kind = Error;
    stage;
    level = Quiet;
    relevance = High;
    message;
    data = [];
    duration_ms = None;
  }
