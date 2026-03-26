val of_node_analysis :
  node_name:Ast.ident ->
  nodes:Ir.node list ->
  node:Ir.node ->
  analysis:Product_build.analysis ->
  Proof_kernel_types.node_ir

val export_node_summary :
  node:Ir.node ->
  normalized_ir:Proof_kernel_types.node_ir ->
  Proof_kernel_types.exported_node_summary_ir
