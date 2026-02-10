(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 *---------------------------------------------------------------------------*)

(** OBC+ ghost instrumentation (pre‑k variables, helper locals). *)

(** Inject ghost variables/assignments into a node. *)
val transform_node_ghost : Ast.node -> Ast.node
(** Same as [transform_node_ghost] but returns metadata. *)
val transform_node_ghost_with_info : Ast.node -> Ast.node * Stage_info.obc_info
