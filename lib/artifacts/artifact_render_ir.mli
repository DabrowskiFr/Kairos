(** Text renderers for raw, annotated, and verified Kairos IR nodes. *)

(*---------------------------------------------------------------------------
 * Kairos — Text renderer for the three IR layers.
 *
 * Produces a human-readable `.kir` representation of raw_node,
 * annotated_node, and verified_node.
 *---------------------------------------------------------------------------*)

val render_raw_node : Proof_obligation_ir.raw_node -> string
val render_annotated_node : Proof_obligation_ir.annotated_node -> string
val render_verified_node : Proof_obligation_ir.verified_node -> string
