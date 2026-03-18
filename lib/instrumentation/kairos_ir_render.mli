(*---------------------------------------------------------------------------
 * Kairos — Text renderer for the three IR layers.
 *
 * Produces a human-readable `.kir` representation of raw_node,
 * annotated_node, and verified_node.
 *---------------------------------------------------------------------------*)

val render_raw_node : Kairos_ir.raw_node -> string
val render_annotated_node : Kairos_ir.annotated_node -> string
val render_verified_node : Kairos_ir.verified_node -> string
