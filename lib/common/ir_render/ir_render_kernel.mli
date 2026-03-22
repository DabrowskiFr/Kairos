(** Renderers for kernel/product IR diagnostic views. *)

val render_historical_clauses : Proof_kernel_ir.node_ir -> string list
val render_eliminated_clauses : Proof_kernel_ir.node_ir -> string list
val render_node_ir : Proof_kernel_ir.node_ir -> string list
