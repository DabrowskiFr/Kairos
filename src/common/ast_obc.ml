type node_info = Ast.obc_info
type transition_info = Ast.transition_attrs
type node = Ast.node
type transition = Ast.transition
type program = Ast.program

let empty_node_info : node_info =
  { ghost_locals_added = [];
    pre_k_infos = [];
    fold_infos = [];
    warnings = []; }
let empty_transition_info : transition_info = Ast.empty_transition_attrs
let node_info (n:node) : node_info =
  match n.attrs.obc_info with
  | Some info -> info
  | None -> empty_node_info
let transition_info (t:transition) : transition_info = t.attrs
let with_node_info (info:node_info) (n:node) : node =
  Ast.with_node_obc_info info n
let with_transition_info (info:transition_info) (t:transition) : transition =
  Ast.with_transition_attrs info t
let invariants_mon (n:node) : Ast.invariant_mon list = Ast.node_invariants_mon n
let with_invariants_mon (invariants_mon:Ast.invariant_mon list) (n:node) : node =
  Ast.with_node_invariants_mon invariants_mon n
let transition_lemmas (t:transition) : Ast.fo_o list = Ast.transition_lemmas t
let transition_ghost (t:transition) : Ast.stmt list = Ast.transition_ghost t
let transition_monitor (t:transition) : Ast.stmt list = Ast.transition_monitor t
let with_transition_lemmas (lemmas:Ast.fo_o list) (t:transition) : transition =
  Ast.with_transition_lemmas lemmas t
let with_transition_ghost (ghost:Ast.stmt list) (t:transition) : transition =
  Ast.with_transition_ghost ghost t
let with_transition_monitor (monitor:Ast.stmt list) (t:transition) : transition =
  Ast.with_transition_monitor monitor t

let node_of_ast (n:Ast.node) : node = n
let node_to_ast (n:node) : Ast.node = n
let transition_of_ast (t:Ast.transition) : transition = t
let transition_to_ast (t:transition) : Ast.transition = t

let of_nodes (p:node list) : program = p
let to_nodes (p:program) : node list = p
let map_nodes (f:node -> node) (p:program) : program =
  List.map f p

let of_ast (p:Ast.program) : program = p
let to_ast (p:program) : Ast.program = p
