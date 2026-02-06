type node_info = Ast.why_info
type transition_info = Ast.transition_attrs
type node = Ast.node
type transition = Ast.transition
type program = Ast.program

let empty_node_info : node_info =
  { vc_count = 0;
    vcid_map = [];
    prefix_fields = None;
    warnings = []; }
let empty_transition_info : transition_info = Ast.empty_transition_attrs
let node_info (n:node) : node_info =
  match n.attrs.why_info with
  | Some info -> info
  | None -> empty_node_info
let transition_info (t:transition) : transition_info = t.attrs
let with_node_info (info:node_info) (n:node) : node =
  Ast.with_node_why_info info n
let with_transition_info (info:transition_info) (t:transition) : transition =
  Ast.with_transition_attrs info t

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
