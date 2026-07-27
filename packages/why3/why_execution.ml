module Contract = Kairos_why3_contract.Why3_contract

let worker_metrics_of_backend (worker : Why_metrics.worker_snapshot) : Contract.worker_metrics =
  {
    worker_id = worker.worker_id;
    input_goal_count = worker.worker_input_goal_count;
    prover_goal_count = worker.worker_prover_goal_count;
    duplicate_goal_count = worker.worker_duplicate_goal_count;
    fallback_count = worker.worker_fallback_count;
    wall_s = worker.worker_wall_s;
    prepare_s = worker.worker_prepare_s;
    print_s = worker.worker_print_s;
    spawn_s = worker.worker_spawn_s;
    wait_s = worker.worker_wait_s;
    solver_s = worker.worker_solver_s;
    last_goal = worker.worker_last_goal;
  }

let execution_metrics_of_backend (metrics : Why_metrics.snapshot) : Contract.execution_metrics =
  {
    setup_s = metrics.why3_setup_s;
    parse_s = metrics.why3_parse_s;
    typecheck_s = metrics.why3_typecheck_s;
    task_extract_s = metrics.why3_task_extract_s;
    split_vc_s = metrics.why3_split_vc_s;
    prepare_s = metrics.why3_prepare_s;
    print_s = metrics.why3_print_s;
    spawn_s = metrics.why3_spawn_s;
    wait_s = metrics.why3_wait_s;
    solver_s = metrics.why3_solver_s;
    input_goal_count = metrics.why3_input_goal_count;
    prover_goal_count = metrics.why3_goal_count;
    duplicate_goal_count = metrics.why3_duplicate_goal_count;
    fallback_count = metrics.why3_fallback_count;
    smt_fingerprint_count = List.length metrics.why3_smt_fingerprints;
    unique_smt_fingerprint_count =
      List.length (List.sort_uniq String.compare metrics.why3_smt_fingerprints);
    workers = List.map worker_metrics_of_backend metrics.why3_workers;
  }

let status_of_answer = function
  | Why3.Call_provers.Valid -> Contract.Valid
  | Why3.Call_provers.Invalid -> Contract.Invalid
  | Why3.Call_provers.Timeout | Why3.Call_provers.StepLimitExceeded -> Contract.Timeout
  | Why3.Call_provers.Unknown message -> Contract.Unknown (Some message)
  | Why3.Call_provers.OutOfMemory -> Contract.Out_of_memory
  | Why3.Call_provers.Failure message | Why3.Call_provers.HighFailure message ->
      Contract.Failure (Some message)

let timing_of_backend (timing : Why_contract_prove.goal_timing) : Contract.goal_timing =
  {
    prepare_s = timing.prepare_s;
    print_s = timing.print_s;
    spawn_s = timing.spawn_s;
    wait_s = timing.wait_s;
    solver_s = timing.solver_s;
  }

let result_of_backend ~goal_index (result : Why_contract_prove.goal_proof_result) :
    Contract.goal_result =
  {
    goal_index;
    goal_name = result.goal_name;
    status = status_of_answer result.prover_result.pr_answer;
    prover_time_s = result.prover_result.pr_time;
    timing = timing_of_backend result.timing;
    dump_path = result.dump_path;
    probe = None;
  }

let descriptor_of_task goal_index task : Contract.goal_descriptor =
  let goal_name =
    try Why_contract_prove.goal_name_of_prepared_task task
    with _ -> Printf.sprintf "vc-%03d" (goal_index + 1)
  in
  { goal_index; goal_name }

let probe_of_backend (probe : Why_native_probe.native_solver_probe) : Contract.solver_probe =
  {
    solver = probe.solver;
    status = probe.status;
    detail = probe.detail;
    model_text = probe.model_text;
    smt_text = probe.smt_text;
  }

let attach_probe ~timeout_s ~ptree (result : Contract.goal_result) =
  if Contract.proof_status_is_valid result.status then result
  else
    let probe =
      Why_native_probe.native_solver_probe_for_goal_of_ptree ~timeout:timeout_s ~ptree
        ~goal_index:result.goal_index ()
      |> Option.map probe_of_backend
    in
    { result with probe }

let execute ?(should_cancel = fun () -> false)
    ?(on_goal_start = fun (_ : Contract.goal_descriptor) -> ())
    ?(on_goal_done = fun (_ : Contract.goal_result) -> ()) (request : Contract.execution_request) =
  (match Contract.validate_execution_request request with
  | Ok () -> ()
  | Error message -> invalid_arg message);
  Why_metrics.reset ();
  let options = request.options in
  let ptree = Why_task_support.ptree_of_text ~filename:request.filename ~text:request.whyml_text in
  let module_ptrees = Why_task_support.module_ptrees_of_ptree ptree in
  let _config, _main, env, _datadir = Why_task_support.setup_env () in
  let tasks =
    if options.split_vc then Why_task_support.normalize_tasks_of_ptrees ~env ~ptrees:module_ptrees
    else Why_task_support.tasks_of_ptrees ~env ~ptrees:module_ptrees
  in
  let goals = List.mapi descriptor_of_task tasks in
  let vc_blocks =
    if options.emit_vc_text then Why_task_dump_render.dump_why3_tasks_with_attrs_of_tasks tasks
    else []
  in
  let smt_blocks =
    if options.emit_smt_text then Why_task_dump_render.dump_smt2_tasks_of_tasks tasks else []
  in
  let results =
    if not options.prove then []
    else
      let finished = ref [] in
      let _ =
        Why_contract_prove.prove_tasks_with_events ~timeout:options.timeout_s ~jobs:options.jobs
          ~dump_failed_smt:options.dump_failed_smt ~should_cancel
          ~on_goal_start:(fun event ->
            on_goal_start { Contract.goal_index = event.goal_index; goal_name = event.goal_name })
          ~on_goal_done:(fun event ->
            let result = result_of_backend ~goal_index:event.goal_index event.result in
            finished := result :: !finished;
            on_goal_done result)
          tasks
      in
      List.sort
        (fun (left : Contract.goal_result) right -> Int.compare left.goal_index right.goal_index)
        !finished
      |>
      if options.diagnose_nonvalid then List.map (attach_probe ~timeout_s:options.timeout_s ~ptree)
      else Fun.id
  in
  let metrics = Why_metrics.snapshot () |> execution_metrics_of_backend in
  Contract.make_execution_response ~goals ~results ~vc_blocks ~smt_blocks ~metrics
