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

let why3_setup_s = ref 0.0
let why3_parse_s = ref 0.0
let why3_typecheck_s = ref 0.0
let why3_task_extract_s = ref 0.0
let why3_split_vc_s = ref 0.0
let why3_prepare_s = ref 0.0
let why3_print_s = ref 0.0
let why3_spawn_s = ref 0.0
let why3_wait_s = ref 0.0
let why3_solver_s = ref 0.0
let why3_input_goal_count = ref 0
let why3_goal_count = ref 0
let why3_duplicate_goal_count = ref 0
let why3_fallback_count = ref 0
let why3_workers = ref []
let why3_smt_fingerprints = ref []

let reset () =
  why3_setup_s := 0.0;
  why3_parse_s := 0.0;
  why3_typecheck_s := 0.0;
  why3_task_extract_s := 0.0;
  why3_split_vc_s := 0.0;
  why3_prepare_s := 0.0;
  why3_print_s := 0.0;
  why3_spawn_s := 0.0;
  why3_wait_s := 0.0;
  why3_solver_s := 0.0;
  why3_input_goal_count := 0;
  why3_goal_count := 0;
  why3_duplicate_goal_count := 0;
  why3_fallback_count := 0;
  why3_workers := [];
  why3_smt_fingerprints := []

let snapshot () =
  {
    why3_setup_s = !why3_setup_s;
    why3_parse_s = !why3_parse_s;
    why3_typecheck_s = !why3_typecheck_s;
    why3_task_extract_s = !why3_task_extract_s;
    why3_split_vc_s = !why3_split_vc_s;
    why3_prepare_s = !why3_prepare_s;
    why3_print_s = !why3_print_s;
    why3_spawn_s = !why3_spawn_s;
    why3_wait_s = !why3_wait_s;
    why3_solver_s = !why3_solver_s;
    why3_input_goal_count = !why3_input_goal_count;
    why3_goal_count = !why3_goal_count;
    why3_duplicate_goal_count = !why3_duplicate_goal_count;
    why3_fallback_count = !why3_fallback_count;
    why3_workers = List.rev !why3_workers;
    why3_smt_fingerprints = List.rev !why3_smt_fingerprints;
  }

let rec drop_prefix count values =
  if count <= 0 then values
  else match values with [] -> [] | _ :: rest -> drop_prefix (count - 1) rest

let diff ~before ~after_ =
  {
    why3_setup_s = max 0.0 (after_.why3_setup_s -. before.why3_setup_s);
    why3_parse_s = max 0.0 (after_.why3_parse_s -. before.why3_parse_s);
    why3_typecheck_s =
      max 0.0 (after_.why3_typecheck_s -. before.why3_typecheck_s);
    why3_task_extract_s =
      max 0.0 (after_.why3_task_extract_s -. before.why3_task_extract_s);
    why3_split_vc_s =
      max 0.0 (after_.why3_split_vc_s -. before.why3_split_vc_s);
    why3_prepare_s = max 0.0 (after_.why3_prepare_s -. before.why3_prepare_s);
    why3_print_s = max 0.0 (after_.why3_print_s -. before.why3_print_s);
    why3_spawn_s = max 0.0 (after_.why3_spawn_s -. before.why3_spawn_s);
    why3_wait_s = max 0.0 (after_.why3_wait_s -. before.why3_wait_s);
    why3_solver_s = max 0.0 (after_.why3_solver_s -. before.why3_solver_s);
    why3_input_goal_count =
      max 0 (after_.why3_input_goal_count - before.why3_input_goal_count);
    why3_goal_count =
      max 0 (after_.why3_goal_count - before.why3_goal_count);
    why3_duplicate_goal_count =
      max 0
        (after_.why3_duplicate_goal_count - before.why3_duplicate_goal_count);
    why3_fallback_count =
      max 0 (after_.why3_fallback_count - before.why3_fallback_count);
    why3_workers =
      drop_prefix (List.length before.why3_workers) after_.why3_workers;
    why3_smt_fingerprints =
      drop_prefix
        (List.length before.why3_smt_fingerprints)
        after_.why3_smt_fingerprints;
  }

let add_snapshot metrics =
  why3_setup_s := !why3_setup_s +. metrics.why3_setup_s;
  why3_parse_s := !why3_parse_s +. metrics.why3_parse_s;
  why3_typecheck_s := !why3_typecheck_s +. metrics.why3_typecheck_s;
  why3_task_extract_s :=
    !why3_task_extract_s +. metrics.why3_task_extract_s;
  why3_split_vc_s := !why3_split_vc_s +. metrics.why3_split_vc_s;
  why3_prepare_s := !why3_prepare_s +. metrics.why3_prepare_s;
  why3_print_s := !why3_print_s +. metrics.why3_print_s;
  why3_spawn_s := !why3_spawn_s +. metrics.why3_spawn_s;
  why3_wait_s := !why3_wait_s +. metrics.why3_wait_s;
  why3_solver_s := !why3_solver_s +. metrics.why3_solver_s;
  why3_input_goal_count :=
    !why3_input_goal_count + metrics.why3_input_goal_count;
  why3_goal_count := !why3_goal_count + metrics.why3_goal_count;
  why3_duplicate_goal_count :=
    !why3_duplicate_goal_count + metrics.why3_duplicate_goal_count;
  why3_fallback_count :=
    !why3_fallback_count + metrics.why3_fallback_count;
  why3_workers := List.rev_append metrics.why3_workers !why3_workers;
  why3_smt_fingerprints :=
    List.rev_append metrics.why3_smt_fingerprints !why3_smt_fingerprints

let add_float counter elapsed_s =
  counter := !counter +. max 0.0 elapsed_s

let record_why3_worker worker = why3_workers := worker :: !why3_workers
let record_why3_setup ~elapsed_s = add_float why3_setup_s elapsed_s
let record_why3_parse ~elapsed_s = add_float why3_parse_s elapsed_s
let record_why3_typecheck ~elapsed_s = add_float why3_typecheck_s elapsed_s
let record_why3_task_extract ~elapsed_s = add_float why3_task_extract_s elapsed_s
let record_why3_split_vc ~elapsed_s = add_float why3_split_vc_s elapsed_s
let record_why3_prepare ~elapsed_s = add_float why3_prepare_s elapsed_s
let record_why3_print ~elapsed_s = add_float why3_print_s elapsed_s
let record_why3_spawn ~elapsed_s = add_float why3_spawn_s elapsed_s

let record_why3_wait ~elapsed_s ~solver_s =
  incr why3_goal_count;
  add_float why3_wait_s elapsed_s;
  add_float why3_solver_s solver_s

let record_why3_input_goals ~count =
  why3_input_goal_count := !why3_input_goal_count + max 0 count

let record_why3_duplicate_goal () = incr why3_duplicate_goal_count
let record_why3_fallback () = incr why3_fallback_count

let record_why3_smt_fingerprint fingerprint =
  why3_smt_fingerprints := fingerprint :: !why3_smt_fingerprints
