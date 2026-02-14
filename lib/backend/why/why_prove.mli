(* Why3 proof execution and task extraction. *)

(* Aggregate counts for VC results. *)
type summary = {
  total : int;
  valid : int;
  invalid : int;
  unknown : int;
  timeout : int;
  failure : int;
}

(* Result of running a proof batch. *)
type result = { status : int; summary : summary }

(* Prove a Why3 theory text with a given prover. *)
val prove_text :
  ?timeout:int -> ?prover_cmd:string -> prover:string -> text:string -> unit -> result

(* Dump Why3 tasks (sequents) as strings. *)
val dump_why3_tasks : text:string -> string list

(* Dump Why3 tasks with attributes preserved. *)
val dump_why3_tasks_with_attrs : text:string -> string list

(* Dump SMT2 tasks for a given prover. *)
val dump_smt2_tasks : prover:string -> text:string -> string list

(* Prove and return per‑goal details (name/status/time/source). *)
val prove_text_detailed :
  ?timeout:int ->
  ?prover_cmd:string ->
  ?selected_goal_index:int ->
  prover:string ->
  text:string ->
  unit ->
  summary * (string * string * float * string option * string * string option) list

(* Same as [prove_text_detailed] but emits callbacks per goal. *)
val prove_text_detailed_with_callbacks :
  ?timeout:int ->
  ?prover_cmd:string ->
  ?selected_goal_index:int ->
  prover:string ->
  text:string ->
  vc_ids_ordered:int list option ->
  on_goal_start:(int -> string -> unit) ->
  on_goal_done:
    (int -> string -> string -> float -> string option -> string -> string option -> unit) ->
  unit ->
  summary * (string * string * float * string option * string * string option) list

(* Extract Why3 goal ids for each task. *)
val task_goal_wids : text:string -> int list list

(* Infer (src,dst) state names per normalized task from Why3 AST structure.
   Returns [None] when source cannot be inferred for a task. *)
val task_state_pairs : text:string -> (string * string) option list

(* Extract sequents as (hypotheses, goal) pairs. *)
val task_sequents : text:string -> (string list * string) list
