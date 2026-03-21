(** Abstract program model used internally by instrumentation and product
    construction. *)

open Ast

type transition = {
  src : ident;
  dst : ident;
  guard : iexpr option;
  requires : ltl_o list;
  ensures : ltl_o list;
  body : stmt list;
  attrs : transition_attrs;
}

type node_semantics = Ast.node_semantics

(* The specification layer keeps the source-level meaning of contracts:
   formulas may mention the current tick and bounded history via [pre_k].
   Backend-introduced memory cells such as [__pre_k...] are compilation artifacts,
   not part of this intermediate specification view. *)
type node_specification = Ast.node_specification

type node = {
  semantics : node_semantics;
  specification : node_specification;
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
