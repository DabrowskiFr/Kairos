let write_optional_output (out : string option) (text : string) : unit =
  match out with
  | None -> ()
  | Some "-" -> print_string text
  | Some file -> Artifact_io.write_text file text

type config = {
  input_file : string;
  dump_why : string option;
  dump_why3_vc : string option;
  dump_smt2 : string option;
  why_translation_mode : Pipeline.why_translation_mode;
  prove : bool;
  prover : string;
  prover_cmd : string option;
}

let run (cfg : config) : (unit, string) result =
  let p_cfg : Pipeline.config =
    {
      input_file = cfg.input_file;
      prover = cfg.prover;
      prover_cmd = cfg.prover_cmd;
      wp_only = false;
      smoke_tests = false;
      timeout_s = 10;
      selected_goal_index = None;
      compute_proof_diagnostics = false;
      prefix_fields = false;
      why_translation_mode = cfg.why_translation_mode;
      prove = cfg.prove;
      generate_vc_text = cfg.dump_why3_vc <> None;
      generate_smt_text = cfg.dump_smt2 <> None;
      generate_monitor_text = false;
      generate_dot_png = false;
    }
  in
  match Pipeline_service.run p_cfg with
  | Error e -> Error (Pipeline.error_to_string e)
  | Ok out ->
      write_optional_output cfg.dump_why out.why_text;
      write_optional_output cfg.dump_why3_vc out.vc_text;
      write_optional_output cfg.dump_smt2 out.smt_text;
      Ok ()
