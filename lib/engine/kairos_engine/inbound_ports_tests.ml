module Mock_pipeline = struct
  let unavailable () = failwith "unexpected port call"

  let instrumentation_pass ~generate_png:_ ~input:_ = unavailable ()
  let why_pass ~proof_optimizations:_ ~input:_ = unavailable ()
  let obligations_pass ~proof_optimizations:_ ~input:_ = unavailable ()
  let cost_report ~proof_optimizations:_ ~input:_ = unavailable ()
  let normalized_program ~proof_optimizations:_ ~input:_ = unavailable ()
  let ir_pretty_dump ~proof_optimizations:_ ~input:_ = unavailable ()
  let run ~input:_ _config = unavailable ()

  let run_with_callbacks ~should_cancel:_ ~input:_ _config
      ~on_outputs_ready:_ ~on_goals_ready:_ ~on_goal_done:_ =
    unavailable ()

  let generate_c ~input:_ =
    Ok
      [
        {
          Kairos_engine.Outbound_ports.file_name = "mock.c";
          contents = "/* mock */";
        };
      ]
end

module Service =
  Kairos_engine.Inbound.Make (struct
    module Pipeline = Mock_pipeline
  end)

let () =
  let input =
    Kairos_engine.Outbound_ports.make_verification_input ~source_path:None
      ~text_hash:None ~warnings:[] ~verification_model:[]
  in
  match Service.generate_c ~input with
  | Ok [ file ] when file.file_name = "mock.c" -> ()
  | Ok _ -> failwith "mock port returned an unexpected generated file"
  | Error _ -> failwith "mock port unexpectedly failed"
