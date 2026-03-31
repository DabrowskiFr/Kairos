type ir_nodes = Pipeline_build.ir_nodes = {
  raw_ir_nodes : Ir.raw_node list;
  annotated_ir_nodes : Ir.annotated_node list;
  verified_ir_nodes : Ir.verified_node list;
  kernel_ir_nodes : Proof_kernel_types.node_ir list;
}

let instrumentation_pass =
  Instrumentation_artifacts.instrumentation_pass
    ~build_ast_with_info:Pipeline_build.build_ast_with_info
    ~stage_meta:Pipeline_outputs.stage_meta
    ~instrumentation_diag_texts:Pipeline_outputs.instrumentation_diag_texts
    ~program_automaton_texts:Pipeline_outputs.program_automaton_texts

let why_pass =
  Pipeline_why.why_pass ~build_ast_with_info:Pipeline_build.build_ast_with_info
    ~stage_meta:Pipeline_outputs.stage_meta

let obligations_pass =
  Pipeline_why.obligations_pass ~build_ast_with_info:Pipeline_build.build_ast_with_info

let normalized_program ~input_file =
  match Pipeline_build.build_ast_with_info ~input_file () with
  | Error _ as err -> err
  | Ok (asts, _infos) -> Ok (Normalized_program_render.render_program asts.instrumentation)

let ir_pretty_dump ~input_file =
  match Pipeline_build.build_ast_with_info ~input_file () with
  | Error _ as err -> err
  | Ok (asts, infos) ->
      let c = Option.value infos.contracts ~default:Stage_info.empty_contracts_info in
      let program : Ir.program =
        {
          nodes = asts.instrumentation;
          contracts_info =
            {
              contract_origin_map = c.contract_origin_map;
              warnings = c.warnings;
            };
        }
      in
      Ok (Artifact_render_ir.render_pretty_program program)

let dump_ir_nodes = Pipeline_build.dump_ir_nodes
let compile_object = Pipeline_build.compile_object

let eval_pass ~input_file ~trace_text ~with_state ~with_locals =
  Simulation_eval.eval_pass ~input_file ~trace_text ~with_state ~with_locals

let run =
  Compile_run.run ~build_ast_with_info:Pipeline_build.build_ast_with_info
    ~build_outputs:Pipeline_outputs.build_outputs

let run_with_callbacks =
  Compile_run.run_with_callbacks ~build_ast_with_info:Pipeline_build.build_ast_with_info
    ~build_outputs:Pipeline_outputs.build_outputs
