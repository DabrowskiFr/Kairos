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

type product_step_class =
  | Safe
  | Bad_assumption
  | Bad_guarantee

type product_contract = {
  program_transition_index : int;
  step_class : product_step_class;
  product_src : product_state;
  product_dst : product_state;
  assume_guard : Fo_formula.t;
  guarantee_guard : Fo_formula.t;
  requires : contract_formula list;
  ensures : contract_formula list;
  forbidden : contract_formula list;
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

type raw_transition = {
  src_state : ident;
  dst_state : ident;
  guard : Fo_formula.t;
  guard_iexpr : iexpr option;
  body_stmts : stmt list;
}

type raw_node = {
  node_name : ident;
  inputs : vdecl list;
  outputs : vdecl list;
  locals : vdecl list;
  control_states : ident list;
  init_state : ident;
  instances : (ident * ident) list;
  pre_k_map : (hexpr * Temporal_support.pre_k_info) list;
  transitions : raw_transition list;
  assumes : ltl list;
  guarantees : ltl list;
}

type annotated_transition = {
  raw : raw_transition;
  requires : contract_formula list;
  ensures : contract_formula list;
}

type annotated_node = {
  raw : raw_node;
  transitions : annotated_transition list;
  coherency_goals : contract_formula list;
  user_invariants : invariant_user list;
}

type verified_transition = {
  src_state : ident;
  dst_state : ident;
  guard : Fo_formula.t;
  guard_iexpr : iexpr option;
  body_stmts : stmt list;
  pre_k_updates : stmt list;
  requires : contract_formula list;
  ensures : contract_formula list;
}

type verified_node = {
  node_name : ident;
  inputs : vdecl list;
  outputs : vdecl list;
  locals : vdecl list;
  control_states : ident list;
  init_state : ident;
  instances : (ident * ident) list;
  transitions : verified_transition list;
  product_transitions : product_contract list;
  assumes : ltl list;
  guarantees : ltl list;
  coherency_goals : contract_formula list;
  user_invariants : invariant_user list;
}

type proof_views = {
  raw : raw_node option;
  annotated : annotated_node option;
  verified : verified_node option;
}

type contracts_info = {
  contract_origin_map : (int * Formula_origin.t option) list;
  warnings : string list;
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
  proof_views : proof_views;
}

type program = {
  nodes : node list;
  contracts_info : contracts_info;
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

val empty_proof_views : proof_views
