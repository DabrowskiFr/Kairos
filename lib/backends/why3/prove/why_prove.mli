(** Why3 proof execution and task extraction. *)

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
  ?should_cancel:(unit -> bool) ->
  prover:string ->
  text:string ->
  unit ->
  summary * (string * string * float * string option * string * string option) list

(* Same as [prove_text_detailed] but emits callbacks per goal. *)
val prove_text_detailed_with_callbacks :
  ?timeout:int ->
  ?prover_cmd:string ->
  ?selected_goal_index:int ->
  ?should_cancel:(unit -> bool) ->
  prover:string ->
  text:string ->
  vc_ids_ordered:int list option ->
  on_goal_start:(int -> string -> unit) ->
  on_goal_done:
    (int -> string -> string -> float -> string option -> string -> string option -> unit) ->
  unit ->
  summary * (string * string * float * string option * string * string option) list

type sequent_term = {
  text : string;
  symbols : string list;
  operators : string list;
  quantifiers : string list;
  has_arithmetic : bool;
  term_size : int;
  hypothesis_ids : int list;
  origin_labels : string list;
  hypothesis_kind : string option;
}

type structured_sequent = {
  hypotheses : sequent_term list;
  goal : sequent_term;
}

type failing_hypothesis_core = {
  kept_hypothesis_ids : int list;
  removed_hypothesis_ids : int list;
}

type native_unsat_core = {
  solver : string;
  hypothesis_ids : int list;
  smt_text : string;
}

type native_solver_probe = {
  solver : string;
  status : string;
  detail : string option;
  model_text : string option;
  smt_text : string;
}

(* Extract Why3 goal ids for each task. *)
val task_goal_wids : text:string -> int list list

(* Infer (src,dst) state names per normalized task from Why3 AST structure.
   Returns [None] when source cannot be inferred for a task. *)
val task_state_pairs : text:string -> (string * string) option list

(* Extract sequents as (hypotheses, goal) pairs. *)
val task_sequents : text:string -> (string list * string) list

(* Extract sequents with term-structure analysis. *)
val task_structured_sequents : text:string -> structured_sequent list

(* For one failed goal, greedily minimize the set of Kairos-instrumented
   hypotheses needed to reproduce a non-valid result. *)
val minimize_failing_hypotheses :
  ?timeout:int ->
  ?prover_cmd:string ->
  prover:string ->
  text:string ->
  goal_index:int ->
  unit ->
  failing_hypothesis_core option

(* Ask the underlying SMT solver for a native unsat core on one targeted goal
   by generating a dedicated named-assertion SMT script. *)
val native_unsat_core_for_goal :
  ?timeout:int ->
  prover:string ->
  text:string ->
  goal_index:int ->
  unit ->
  native_unsat_core option

(* Probe one targeted goal directly through the native SMT solver, capturing a
   finer status classification and a model/counterexample payload when the VC is
   satisfiable. *)
val native_solver_probe_for_goal :
  ?timeout:int ->
  prover:string ->
  text:string ->
  goal_index:int ->
  unit ->
  native_solver_probe option
