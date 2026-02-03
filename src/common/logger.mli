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

val parse_level : string -> (level, string) result
val parse_format : string -> (format, string) result
val parse_color : string -> (color, string) result

val default_config : config
val set_config : config -> unit
val get_config : unit -> config

val emit : event -> unit

val stage_start : Stage_names.stage_id -> unit
val stage_end : Stage_names.stage_id -> int -> (string * string) list -> unit
val stage_info : Stage_names.stage_id -> string -> (string * string) list -> unit
val output_written : string -> string -> int -> unit
val warning : ?stage:Stage_names.stage_id -> string -> unit
val error : ?stage:Stage_names.stage_id -> string -> unit
