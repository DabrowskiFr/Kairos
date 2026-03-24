(** Abstract program model used internally by instrumentation and product
    construction. *)

open Ast

type contract_formula = {
  value : ltl;
  origin : Formula_origin.t option;
  oid : int;
  loc : loc option;
}
[@@deriving yojson]

type transition = {
  src : ident;
  dst : ident;
  guard : iexpr option;
  requires : contract_formula list;
  ensures : contract_formula list;
  body : stmt list;
  uid : int option;
  warnings : string list;
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
  uid : int option;
  user_invariants : invariant_user list;
  coherency_goals : contract_formula list;
}

val of_ast_transition : Ast.transition -> transition
val to_ast_transition : transition -> Ast.transition
val of_ast_contract_formula : ?origin:Formula_origin.t -> Ast.ltl_o -> contract_formula
val to_ast_contract_formula : contract_formula -> Ast.ltl_o
val of_ast_node : Ast.node -> node
val to_ast_node : node -> Ast.node
val with_origin : ?loc:loc -> Formula_origin.t -> ltl -> contract_formula
val map_formula : (ltl -> ltl) -> contract_formula -> contract_formula
val values : contract_formula list -> ltl list
val map_transitions : (transition list -> transition list) -> node -> node
val render_transition : ?indent:int -> transition -> string
val render_node : node -> string
val render_program : node list -> string
