open Pipeline

let default_cfg input_file : Pipeline.config =
  {
    input_file;
    prover = "z3";
    prover_cmd = None;
    wp_only = false;
    smoke_tests = false;
    timeout_s = 5;
    max_proof_goals = None;
    selected_goal_index = None;
    compute_proof_diagnostics = false;
    prefix_fields = false;
    prove = false;
    generate_vc_text = false;
    generate_smt_text = false;
    generate_monitor_text = false;
    generate_dot_png = false;
  }

let () =
  if Array.length Sys.argv < 3 then (
    prerr_endline "usage: probe_v2_goal <file.kairos> <goal-index>";
    exit 2);
  let input_file = Sys.argv.(1) in
  let goal_index = int_of_string Sys.argv.(2) in
  match Pipeline_v2_indep.run (default_cfg input_file) with
  | Error e ->
      prerr_endline (Pipeline.error_to_string e);
      exit 1
  | Ok out -> (
      match
        Why_prove.native_solver_probe_for_goal ~timeout:5 ~prover:"z3" ~text:out.why_text
          ~goal_index ()
      with
      | None ->
          print_endline "null"
      | Some probe ->
          Printf.printf "status=%s\n" probe.status;
          Option.iter (fun detail -> Printf.printf "detail=%s\n" detail) probe.detail;
          Option.iter (fun model -> Printf.printf "model=%s\n" model) probe.model_text;
          Printf.printf "smt:\n%s\n" probe.smt_text)
