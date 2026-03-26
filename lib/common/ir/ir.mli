(** Normalized program representation used by the middle-end. *)

open Ast

type contract_formula = {
  value : ltl;
  origin : Formula_origin.t option;
  oid : int;
  loc : loc option;
}
[@@deriving yojson]

type product_state = {
  prog_state : ident;
  assume_state_index : int;
  guarantee_state_index : int;
}

type product_contract = {
  program_transition_index : int;
  product_src : product_state;
  product_dst : product_state;
  assume_guard : Fo_formula.t;
  guarantee_guard : Fo_formula.t;
  requires : contract_formula list;
  ensures : contract_formula list;
}

(** Normalized transition.

    This record combines:
    {ul
    {- source control-flow information;}
    {- generated transition contracts;}
    {- the executable statement body;}
    {- per-transition warnings.}} *)
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

type source_info = {
  assumes : ltl list;
  guarantees : ltl list;
  user_invariants : invariant_user list;
  state_invariants : invariant_state_rel list;
}

(** Normalized node consumed by the middle-end.

    The record keeps:
    {ul
    {- source semantics;}
    {- normalized transitions;}
    {- product-specialized transitions;}
    {- source information kept for traceability and export;}
    {- coherency goals.}} *)
type node = {
  semantics : node_semantics;
  trans : transition list;
  product_transitions : product_contract list;
  uid : int option;
  source_info : source_info;
  coherency_goals : contract_formula list;
}

(** Forget normalized contract metadata and recover a plain source
    transition. *)
val to_ast_transition : transition -> Ast.transition

(** Project a normalized contract formula back to the source-style wrapper used
    for stable ids and source locations. *)
val to_ast_contract_formula : contract_formula -> Ast.ltl_o

(** Forget normalized metadata and recover a source node. *)
val to_ast_node : node -> Ast.node

(** Build a contract formula with a fresh provenance id. *)
val with_origin : ?loc:loc -> Formula_origin.t -> ltl -> contract_formula

(** Rewrite the logical payload of a contract formula while preserving origin,
    id, and source location. *)
val map_formula : (ltl -> ltl) -> contract_formula -> contract_formula

(** Extract the raw logical formulas carried by a list of normalized contract
    formulas. *)
val values : contract_formula list -> ltl list

val map_product_contract_formulas :
  contract:(ltl -> ltl) ->
  guard:(Fo_formula.t -> Fo_formula.t) ->
  product_contract ->
  product_contract

(** Rewrite the transition list of a node while preserving the other fields. *)
val map_transitions : (transition list -> transition list) -> node -> node
