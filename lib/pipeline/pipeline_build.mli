(** Imported AST construction and IR/object extraction for the main pipeline. *)

type ir_nodes = {
  raw_ir_nodes : Proof_obligation_ir.raw_node list;
  annotated_ir_nodes : Proof_obligation_ir.annotated_node list;
  verified_ir_nodes : Proof_obligation_ir.verified_node list;
  kernel_ir_nodes : Proof_kernel_ir.node_ir list;
}

val build_ast_with_info :
  input_file:string ->
  unit ->
  (Pipeline.ast_stages * Pipeline.stage_infos, Pipeline.error) result

val dump_ir_nodes : input_file:string -> (ir_nodes, Pipeline.error) result

val compile_object :
  input_file:string -> (Kairos_object.t, Pipeline.error) result
