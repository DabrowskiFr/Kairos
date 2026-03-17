type raw_transition = {
  src_state            : Ast.ident;
  dst_state            : Ast.ident;
  guard                : Ast.fo;
  guard_iexpr          : Ast.iexpr option;
  ghost_stmts          : Ast.stmt list;
  body_stmts           : Ast.stmt list;
  instrumentation_stmts: Ast.stmt list;
}

type raw_node = {
  node_name     : Ast.ident;
  inputs        : Ast.vdecl list;
  outputs       : Ast.vdecl list;
  locals        : Ast.vdecl list;
  control_states: Ast.ident list;
  init_state    : Ast.ident;
  pre_k_map     : (Ast.hexpr * Support.pre_k_info) list;
  transitions   : raw_transition list;
  assumes       : Ast.fo_ltl list;
  guarantees    : Ast.fo_ltl list;
}

type annotated_transition = {
  raw     : raw_transition;
  requires: Ast.fo_o list;
  ensures : Ast.fo_o list;
}

type annotated_node = {
  raw              : raw_node;
  transitions      : annotated_transition list;
  coherency_goals  : Ast.fo_o list;
  user_invariants  : Ast.invariant_user list;
  state_invariants : Ast.invariant_state_rel list;
}

type verified_transition = {
  src_state            : Ast.ident;
  dst_state            : Ast.ident;
  guard                : Ast.fo;
  guard_iexpr          : Ast.iexpr option;
  ghost_stmts          : Ast.stmt list;
  body_stmts           : Ast.stmt list;
  instrumentation_stmts: Ast.stmt list;
  pre_k_updates        : Ast.stmt list;
  requires             : Ast.fo_o list;
  ensures              : Ast.fo_o list;
}

type verified_node = {
  node_name        : Ast.ident;
  inputs           : Ast.vdecl list;
  outputs          : Ast.vdecl list;
  locals           : Ast.vdecl list;
  control_states   : Ast.ident list;
  init_state       : Ast.ident;
  transitions      : verified_transition list;
  assumes          : Ast.fo_ltl list;
  guarantees       : Ast.fo_ltl list;
  coherency_goals  : Ast.fo_o list;
  user_invariants  : Ast.invariant_user list;
  state_invariants : Ast.invariant_state_rel list;
}
