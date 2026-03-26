type ir_nodes = Pipeline_build.ir_nodes = {
  raw_ir_nodes : Proof_obligation_ir.raw_node list;
  annotated_ir_nodes : Proof_obligation_ir.annotated_node list;
  verified_ir_nodes : Proof_obligation_ir.verified_node list;
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
    ~with_why_translation_mode:Pipeline_outputs.with_why_translation_mode

let obligations_pass =
  Pipeline_why.obligations_pass ~build_ast_with_info:Pipeline_build.build_ast_with_info
    ~with_why_translation_mode:Pipeline_outputs.with_why_translation_mode

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
