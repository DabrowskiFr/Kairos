open Pipeline

let () =
  if Array.length Sys.argv < 2 then (
    prerr_endline "usage: emit_why_v2 <file.kairos>";
    exit 2);
  let file = Sys.argv.(1) in
  let cfg : Pipeline.config =
    {
      input_file = file;
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
  in
  match Pipeline_v2_indep.run cfg with
  | Error e ->
      prerr_endline (Pipeline.error_to_string e);
      exit 1
  | Ok out -> print_string out.why_text
