(** Kernel IR exported by the product/instrumentation pipeline and consumed by
    Why generation, modular imports, and debug tooling. *)

include module type of struct
  include Proof_kernel_types
end

val phase_state_case_name : prog_state:Ast.ident -> guarantee_state:int -> string
val phase_step_pre_case_name : product_step_ir -> string
val phase_step_post_case_name : product_step_ir -> string

val has_effective_product_coverage : node_ir -> bool

val of_node_analysis :
  node_name:Ast.ident ->
  nodes:Normalized_program.node list ->
  node:Normalized_program.node ->
  analysis:Product_build.analysis ->
  node_ir

val node_signature_of_ast : Ast.node -> node_signature_ir

val export_node_summary :
  node:Normalized_program.node ->
  normalized_ir:node_ir ->
  exported_node_summary_ir
