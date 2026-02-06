type summary = {
  total : int;
  valid : int;
  invalid : int;
  unknown : int;
  timeout : int;
  failure : int;
}

type result = {
  status : int;
  summary : summary;
}

val prove_text :
  ?timeout:int -> ?prover_cmd:string -> prover:string -> text:string -> unit -> result

val dump_why3_tasks : text:string -> string list
val dump_why3_tasks_with_attrs : text:string -> string list

val dump_smt2_tasks : prover:string -> text:string -> string list

val prove_text_detailed :
  ?timeout:int ->
  ?prover_cmd:string ->
  prover:string ->
  text:string ->
  unit ->
  summary * (string * string * float * string option * string * string option) list

val prove_text_detailed_with_callbacks :
  ?timeout:int ->
  ?prover_cmd:string ->
  prover:string ->
  text:string ->
  vc_ids_ordered:int list option ->
  on_goal_start:(int -> string -> unit) ->
  on_goal_done:(int -> string -> string -> float -> string option -> string -> string option -> unit) ->
  unit ->
  summary * (string * string * float * string option * string * string option) list

val task_goal_wids : text:string -> int list list

val task_sequents :
  text:string -> (string list * string) list
