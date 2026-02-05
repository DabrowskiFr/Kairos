val setup : level:Logs.level option -> log_file:string option -> unit
val debug : string -> unit
val info : string -> unit
val stage_start : Stage_names.stage_id -> unit
val stage_end : Stage_names.stage_id -> int -> (string * string) list -> unit
val stage_info : Stage_names.stage_id option -> string -> (string * string) list -> unit
val output_written : string -> string -> int -> unit
val warning : ?stage:Stage_names.stage_id -> string -> unit
val error : ?stage:Stage_names.stage_id -> string -> unit
