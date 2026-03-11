type run_config = {
  input_file : string;
  dump_obc : string option;
  dump_obc_abstract : bool;
  dump_why : string option;
  dump_why3_vc : string option;
  dump_smt2 : string option;
  prove : bool;
  prover : string;
  prover_cmd : string option;
}

let write_optional_output (out : string option) (text : string) : unit =
  match out with
  | None -> ()
  | Some "-" -> print_string text
  | Some file -> Io.write_text file text

let run (cfg : run_config) : (unit, string) result =
  let p_cfg : Pipeline.config =
    {
      input_file = cfg.input_file;
      prover = cfg.prover;
      prover_cmd = cfg.prover_cmd;
      wp_only = false;
      smoke_tests = false;
      timeout_s = 10;
      max_proof_goals = None;
      selected_goal_index = None;
      compute_proof_diagnostics = false;
      prefix_fields = false;
      prove = cfg.prove;
      generate_vc_text = cfg.dump_why3_vc <> None;
      generate_smt_text = cfg.dump_smt2 <> None;
      generate_monitor_text = false;
      generate_dot_png = false;
    }
  in
  match Pipeline_v2_indep.run p_cfg with
  | Error e -> Error (Pipeline.error_to_string e)
  | Ok out ->
      let obc_text = if cfg.dump_obc_abstract then out.obc_text else out.obc_text in
      write_optional_output cfg.dump_obc obc_text;
      write_optional_output cfg.dump_why out.why_text;
      write_optional_output cfg.dump_why3_vc out.vc_text;
      write_optional_output cfg.dump_smt2 out.smt_text;
      Ok ()
