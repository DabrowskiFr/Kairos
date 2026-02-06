type node
type transition
type node_info = Ast.obc_info
type transition_info = Ast.transition_attrs
type program

val empty_node_info : node_info
val empty_transition_info : transition_info
val node_info : node -> node_info
val transition_info : transition -> transition_info
val with_node_info : node_info -> node -> node
val with_transition_info : transition_info -> transition -> transition
val invariants_mon : node -> Ast.invariant_mon list
val with_invariants_mon : Ast.invariant_mon list -> node -> node
val transition_lemmas : transition -> Ast.fo_o list
val transition_ghost : transition -> Ast.stmt list
val transition_monitor : transition -> Ast.stmt list
val with_transition_lemmas : Ast.fo_o list -> transition -> transition
val with_transition_ghost : Ast.stmt list -> transition -> transition
val with_transition_monitor : Ast.stmt list -> transition -> transition

val of_nodes : node list -> program
val to_nodes : program -> node list
val map_nodes : (node -> node) -> program -> program

val of_ast : Ast.program -> program
val to_ast : program -> Ast.program
val node_of_ast : Ast.node -> node
val node_to_ast : node -> Ast.node
val transition_of_ast : Ast.transition -> transition
val transition_to_ast : transition -> Ast.transition
