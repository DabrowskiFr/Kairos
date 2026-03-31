(** Text renderers for raw, annotated, and verified Kairos IR nodes. *)

(*---------------------------------------------------------------------------
 * Kairos — Text renderer for the three IR layers.
 *
 * Produces a human-readable `.kir` representation of raw_node,
 * annotated_node, and verified_node.
 *---------------------------------------------------------------------------*)

val render_raw_node : Ir.raw_node -> string
val render_annotated_node : Ir.annotated_node -> string
val render_verified_node : Ir.verified_node -> string

(** Render a full IR program with canonical-contract sections and proof_views.

    The output is intended to be readable while preserving all IR fields. *)
val render_pretty_program : Ir.program -> string
