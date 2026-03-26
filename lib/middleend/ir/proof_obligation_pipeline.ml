let empty_instrumentation_info () : Stage_info.instrumentation_info =
  {
    Stage_info.kernel_ir_nodes = [];
    Stage_info.exported_node_summaries = [];
    Stage_info.raw_ir_nodes = [];
    Stage_info.annotated_ir_nodes = [];
    Stage_info.verified_ir_nodes = [];
    Stage_info.kernel_pipeline_lines = [];
    Stage_info.warnings = [];
    Stage_info.guarantee_automaton_lines = [];
    Stage_info.assume_automaton_lines = [];
    Stage_info.product_lines = [];
    Stage_info.obligations_lines = [];
    Stage_info.prune_lines = [];
    Stage_info.guarantee_automaton_dot = "";
    Stage_info.assume_automaton_dot = "";
    Stage_info.product_dot = "";
  }

let build_instrumentation_info ~(build : Automaton_types.automata_build) ?nodes (node : Ir.node) :
    Stage_info.instrumentation_info =
  let nodes = Option.value nodes ~default:[ node ] in
  let product_analysis = Product_build.analyze_node ~build ~node in
  let raw_ir = Proof_obligation_raw.build_raw_node node in
  let annotated_ir =
    Proof_obligation_annotate.annotate ~raw:raw_ir ~node ~analysis:product_analysis
  in
  let verified_ir = Proof_obligation_lowering.eliminate annotated_ir in
  let rendered =
    Ir_render_product.render ~node_name:node.semantics.sem_nname ~analysis:product_analysis
  in
  let kernel_ir =
    Proof_kernel_build.of_node_analysis ~node_name:node.semantics.sem_nname ~nodes ~node
      ~analysis:product_analysis
  in
  let exported_summary =
    Proof_kernel_build.export_node_summary ~node ~normalized_ir:kernel_ir
  in
  {
    (empty_instrumentation_info ()) with
    Stage_info.kernel_ir_nodes = [ kernel_ir ];
    Stage_info.exported_node_summaries = [ exported_summary ];
    Stage_info.raw_ir_nodes = [ raw_ir ];
    Stage_info.annotated_ir_nodes = [ annotated_ir ];
    Stage_info.verified_ir_nodes = [ verified_ir ];
    Stage_info.kernel_pipeline_lines = Ir_render_kernel.render_node_ir kernel_ir;
    Stage_info.guarantee_automaton_lines = rendered.guarantee_automaton_lines;
    Stage_info.assume_automaton_lines = rendered.assume_automaton_lines;
    Stage_info.product_lines = rendered.product_lines;
    Stage_info.obligations_lines = rendered.obligations_lines;
    Stage_info.prune_lines = rendered.prune_lines;
    Stage_info.guarantee_automaton_dot = rendered.guarantee_automaton_dot;
    Stage_info.assume_automaton_dot = rendered.assume_automaton_dot;
    Stage_info.product_dot = rendered.product_dot;
  }
