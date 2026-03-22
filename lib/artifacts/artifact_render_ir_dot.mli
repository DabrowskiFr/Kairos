(** DOT renderers for the annotated, verified, and kernel IR layers. *)

(*---------------------------------------------------------------------------
 * Kairos — DOT graph renderer for the three IR layers.
 *
 * Produces Graphviz DOT representations of IR nodes for visualization.
 *---------------------------------------------------------------------------*)

val dot_of_annotated_node : Proof_obligation_ir.annotated_node -> string
val dot_of_verified_node : Proof_obligation_ir.verified_node -> string
val dot_of_kernel_node_ir : Proof_kernel_ir.node_ir -> string
