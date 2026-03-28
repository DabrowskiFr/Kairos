(** Pass 3: populate the raw proof-obligation view inside the IR. *)

val apply_node : Ir.node -> Ir.node
val apply_program : Ir.node list -> Ir.node list
