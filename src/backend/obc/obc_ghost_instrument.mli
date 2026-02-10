(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 *---------------------------------------------------------------------------*)

val transform_node_ghost : Ast.node -> Ast.node
val transform_node_ghost_with_info : Ast.node -> Ast.node * Stage_info.obc_info
