(*---------------------------------------------------------------------------
 * Kairos — DOT graph renderer for the three IR layers.
 *
 * Produces Graphviz DOT representations of IR nodes for visualization.
 *---------------------------------------------------------------------------*)

val dot_of_annotated_node : Kairos_ir.annotated_node -> string
val dot_of_verified_node : Kairos_ir.verified_node -> string
val dot_of_kernel_node_ir : Product_kernel_ir.node_ir -> string
