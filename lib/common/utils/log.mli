(* Logging helpers used by CLI/IDE. *)

(** Configure logging level and optional file output. *)
val setup : level:Logs.level option -> log_file:string option -> unit
(** Emit a debug message. *)
val debug : string -> unit
(** Emit an info message. *)
val info : string -> unit
(** Mark the start of a stage (for timing). *)
val stage_start : Stage_names.stage_id -> unit
(** Mark the end of a stage with elapsed ms and key/value stats. *)
val stage_end : Stage_names.stage_id -> int -> (string * string) list -> unit
(** Emit a structured info message for a stage (or global). *)
val stage_info : Stage_names.stage_id option -> string -> (string * string) list -> unit
(** Report that an output file was written (path, kind, bytes). *)
val output_written : string -> string -> int -> unit
(** Emit a warning (optionally tied to a stage). *)
val warning : ?stage:Stage_names.stage_id -> string -> unit
(** Emit an error (optionally tied to a stage). *)
val error : ?stage:Stage_names.stage_id -> string -> unit
