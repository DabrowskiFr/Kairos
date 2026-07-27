(** Process-local technical measurements owned by the Why3 adapter. *)

type worker_snapshot = {
  worker_id : int;
  worker_input_goal_count : int;
  worker_prover_goal_count : int;
  worker_duplicate_goal_count : int;
  worker_fallback_count : int;
  worker_wall_s : float;
  worker_prepare_s : float;
  worker_print_s : float;
  worker_spawn_s : float;
  worker_wait_s : float;
  worker_solver_s : float;
  worker_last_goal : string;
}

type snapshot = {
  why3_setup_s : float;
  why3_parse_s : float;
  why3_typecheck_s : float;
  why3_task_extract_s : float;
  why3_split_vc_s : float;
  why3_prepare_s : float;
  why3_print_s : float;
  why3_spawn_s : float;
  why3_wait_s : float;
  why3_solver_s : float;
  why3_input_goal_count : int;
  why3_goal_count : int;
  why3_duplicate_goal_count : int;
  why3_fallback_count : int;
  why3_workers : worker_snapshot list;
  why3_smt_fingerprints : string list;
}

val reset : unit -> unit
val snapshot : unit -> snapshot
val diff : before:snapshot -> after_:snapshot -> snapshot
val add_snapshot : snapshot -> unit
val record_why3_worker : worker_snapshot -> unit
val record_why3_setup : elapsed_s:float -> unit
val record_why3_parse : elapsed_s:float -> unit
val record_why3_typecheck : elapsed_s:float -> unit
val record_why3_task_extract : elapsed_s:float -> unit
val record_why3_split_vc : elapsed_s:float -> unit
val record_why3_prepare : elapsed_s:float -> unit
val record_why3_print : elapsed_s:float -> unit
val record_why3_spawn : elapsed_s:float -> unit
val record_why3_wait : elapsed_s:float -> solver_s:float -> unit
val record_why3_input_goals : count:int -> unit
val record_why3_duplicate_goal : unit -> unit
val record_why3_fallback : unit -> unit
val record_why3_smt_fingerprint : string -> unit
