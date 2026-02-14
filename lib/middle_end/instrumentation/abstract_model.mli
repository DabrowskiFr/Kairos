open Ast

type transition = {
  src : ident;
  dst : ident;
  guard : iexpr option;
  requires : fo_o list;
  ensures : fo_o list;
  body : stmt list;
  attrs : transition_attrs;
}

type node = {
  nname : ident;
  inputs : vdecl list;
  outputs : vdecl list;
  assumes : fo_ltl list;
  guarantees : fo_ltl list;
  instances : (ident * ident) list;
  locals : vdecl list;
  states : ident list;
  init_state : ident;
  trans : transition list;
  attrs : node_attrs;
}

val of_ast_transition : Ast.transition -> transition
val to_ast_transition : transition -> Ast.transition
val of_ast_node : Ast.node -> node
val to_ast_node : node -> Ast.node
val map_transitions : (transition list -> transition list) -> node -> node
val render_transition : ?indent:int -> transition -> string
val render_node : node -> string
val render_program : node list -> string

type product_triple = int * int * int

val mk_triple : int -> int -> int -> product_triple
val prog_idx : product_triple -> int
val assume_idx : product_triple -> int
val guarantee_idx : product_triple -> int
val is_bad_guarantee : g_bad_idx:int -> product_triple -> bool

type local_combo = {
  gp : fo;
  fg : fo;
  fa : fo;
  qa_src : int;
  qg_src : int;
  qa_dst : int;
  qg_dst : int;
}

val combo_formula : local_combo -> fo
val is_safe_successor : a_bad_idx:int -> g_bad_idx:int -> local_combo -> bool
val is_badg_successor : a_bad_idx:int -> g_bad_idx:int -> local_combo -> bool

type transition_annotation = { req_hyp : fo_o list; ens_obl : fo_o list }

val empty_transition_annotation : transition_annotation
