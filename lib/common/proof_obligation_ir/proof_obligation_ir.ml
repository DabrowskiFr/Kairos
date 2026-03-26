type raw_transition = {
  src_state            : Ast.ident;
  dst_state            : Ast.ident;
  guard                : Fo_formula.t;
  guard_iexpr          : Ast.iexpr option;
  body_stmts           : Ast.stmt list;
}

type raw_node = {
  node_name     : Ast.ident;
  inputs        : Ast.vdecl list;
  outputs       : Ast.vdecl list;
  locals        : Ast.vdecl list;
  control_states: Ast.ident list;
  init_state    : Ast.ident;
  instances     : (Ast.ident * Ast.ident) list;
  pre_k_map     : (Ast.hexpr * Temporal_support.pre_k_info) list;
  transitions   : raw_transition list;
  assumes       : Ast.ltl list;
  guarantees    : Ast.ltl list;
}

type annotated_transition = {
  raw     : raw_transition;
  requires: Ir.contract_formula list;
  ensures : Ir.contract_formula list;
}

type annotated_node = {
  raw              : raw_node;
  transitions      : annotated_transition list;
  coherency_goals  : Ir.contract_formula list;
  user_invariants  : Ast.invariant_user list;
}

type verified_transition = {
  src_state            : Ast.ident;
  dst_state            : Ast.ident;
  guard                : Fo_formula.t;
  guard_iexpr          : Ast.iexpr option;
  body_stmts           : Ast.stmt list;
  pre_k_updates        : Ast.stmt list;
  requires             : Ir.contract_formula list;
  ensures              : Ir.contract_formula list;
}

type verified_node = {
  node_name        : Ast.ident;
  inputs           : Ast.vdecl list;
  outputs          : Ast.vdecl list;
  locals           : Ast.vdecl list;
  control_states   : Ast.ident list;
  init_state       : Ast.ident;
  instances        : (Ast.ident * Ast.ident) list;
  transitions      : verified_transition list;
  assumes          : Ast.ltl list;
  guarantees       : Ast.ltl list;
  coherency_goals  : Ir.contract_formula list;
  user_invariants  : Ast.invariant_user list;
}
