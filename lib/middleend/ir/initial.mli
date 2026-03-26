(** Materialize node-level initial obligations. *)

val apply : Ir.node -> Ir.node

val apply_program : Ir.node list -> Ir.node list
