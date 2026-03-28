(** DOT renderers for the annotated, verified, and kernel IR layers. *)

(*---------------------------------------------------------------------------
 * Kairos — DOT graph renderer for the three IR layers.
 *
 * Produces Graphviz DOT representations of IR nodes for visualization.
 *---------------------------------------------------------------------------*)

val dot_of_annotated_node : Ir.annotated_node -> string
val dot_of_verified_node : Ir.verified_node -> string
val dot_of_kernel_node_ir : Proof_kernel_types.node_ir -> string
