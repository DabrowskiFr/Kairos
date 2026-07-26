module Contract = Kairos_proof_contract.Proof_backend_contract

let join_blocks ~sep blocks =
  let buffer = Buffer.create 4096 in
  List.iteri
    (fun index block ->
      if index > 0 then Buffer.add_string buffer sep;
      Buffer.add_string buffer block)
    blocks;
  Buffer.contents buffer

let run (request : Contract.request) =
  (match Contract.validate_request request with
  | Ok () -> ()
  | Error message -> invalid_arg message);
  let _config, _main, env, _datadir = Why_task_support.setup_env () in
  let tasks =
    Why_task_support.normalize_tasks_of_text ~env ~filename:request.filename
      ~text:request.whyml_text
  in
  let vc_text =
    Why_task_dump_render.dump_why3_tasks_with_attrs_of_tasks tasks
    |> join_blocks ~sep:"\n(* ---- goal ---- *)\n"
  in
  let smt_text =
    Why_task_dump_render.dump_smt2_tasks_of_tasks tasks |> join_blocks ~sep:"\n; ---- goal ----\n"
  in
  Contract.make_response ~vc_text ~smt_text
