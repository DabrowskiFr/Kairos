open Pipeline

let default_cfg input_file timeout_s : Pipeline.config =
  {
    input_file;
    prover = "z3";
    prover_cmd = None;
    wp_only = false;
    smoke_tests = false;
    timeout_s;
    max_proof_goals = None;
    selected_goal_index = None;
    compute_proof_diagnostics = false;
    prefix_fields = false;
    prove = true;
    generate_vc_text = false;
    generate_smt_text = false;
    generate_monitor_text = false;
    generate_dot_png = false;
  }

let json_of_trace (trace : Pipeline.proof_trace) : Yojson.Safe.t =
  `Assoc
    [
      ("goal_index", `Int trace.goal_index);
      ("goal_name", `String trace.goal_name);
      ("status", `String trace.status);
      ("solver_status", `String trace.solver_status);
      ("time_s", `Float trace.time_s);
      ( "vc_id",
        match trace.vc_id with
        | None -> `Null
        | Some vcid -> `String vcid );
    ]

let () =
  if Array.length Sys.argv < 2 || Array.length Sys.argv > 3 then (
    prerr_endline "usage: prove_v2_json <file.kairos> [timeout_s]";
    exit 2);
  let input_file = Sys.argv.(1) in
  let timeout_s = if Array.length Sys.argv = 3 then int_of_string Sys.argv.(2) else 5 in
  match Pipeline_v2_indep.run (default_cfg input_file timeout_s) with
  | Error e ->
      prerr_endline (Pipeline.error_to_string e);
      exit 1
  | Ok out ->
      out.proof_traces |> List.map json_of_trace |> fun traces ->
      Yojson.Safe.pretty_to_channel stdout (`List traces);
      print_newline ()
