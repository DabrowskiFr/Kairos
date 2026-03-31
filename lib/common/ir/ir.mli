(** Intermediate representation used by the middle-end. *)

open Ir_shared_types

(** Logical formula carried by generated contracts.

    Fields:
    {ul
    {- [value]: logical payload;}
    {- [origin]: optional generation origin;}
    {- [oid]: stable identifier used across exports/reports;}
    {- [loc]: optional source location.}} *)
type contract_formula = {
  value : ltl;
  origin : Formula_origin.t option;
  oid : int;
  loc : loc option;
}
[@@deriving yojson]

(** Reachable state in the synchronous product
    [(program state, assume automaton state, guarantee automaton state)]. *)
type product_state = {
  prog_state : ident;
  assume_state_index : int;
  guarantee_state_index : int;
}

(** Classification of one product step.

    Constructors:
    {ul
    {- [Safe]: compatible with both assume and guarantee;}
    {- [Bad_assumption]: assume violation;}
    {- [Bad_guarantee]: guarantee violation only.}} 
    if a step violates both assume and guarantee, it is classified as
    [Bad_assumption].
    *)
type product_step_class =
  | Safe
  | Bad_assumption
  | Bad_guarantee

(** Residual case attached to a canonical product contract.

    Fields:
    {ul
    {- [step_class]: branch class;}
    {- [product_dst]: destination product state;}
    {- [guarantee_guard]: guarantee-side selector guard;}
    {- [propagates]: formulas propagated by this branch to the next step.
       In the current pipeline they are produced from safe guarantee guards
       (origin [GuaranteeAutomaton]) during [post], then consumed by [pre]:
       [pre] keeps those formulas, shifts them with
       [shift_ltl_forward_inputs], and injects the result into destination
       canonical [requires] with origin [GuaranteePropagation].}
    {- [ensures]: branch-specific postconditions;}
    {- [forbidden]: forbidden formulas (typically bad-guarantee).}} *)
type product_case = {
  step_class : product_step_class;
  product_dst : product_state;
  guarantee_guard : Fo_formula.t;
  propagates : contract_formula list;
  ensures : contract_formula list;
  forbidden : contract_formula list;
}

(** Canonical contract for a product-step group.

    A contract factors all steps sharing:
    {ul
    {- the same program transition;}
    {- the same product source;}
    {- the same assume guard.}}

    The [safe_*] fields store the already-computed safe summary consumed by the
    Why backend, while [cases] keeps branch-level details for diagnostics and
    exports.

    Fields:
    {ul
    {- [program_transition_index]: index into [node.trans];}
    {- [product_src]: common source product state;}
    {- [assume_guard]: common assume-side guard;}
    {- [requires]: common preconditions;}
    {- [ensures]: common postconditions;}
    {- [safe_product_dst]: destination of the canonical safe summary, if any;}
    {- [safe_guarantee_guard]: combined safe guarantee guard, if any;}
    {- [safe_propagates]: combined propagated formulas for safe summary;}
    {- [safe_ensures]: combined ensures for safe summary;}
    {- [cases]: residual branch-level cases.}} *)
type product_contract = {
  program_transition_index : int;
  product_src : product_state;
  assume_guard : Fo_formula.t;
  requires : contract_formula list;
  ensures : contract_formula list;
  safe_product_dst : product_state option;
  safe_guarantee_guard : Fo_formula.t option;
  safe_propagates : contract_formula list;
  safe_ensures : contract_formula list;
  cases : product_case list;
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
  warnings : string list;
}

type node_semantics = Ast.node_semantics

(** Source-level contractual information kept alongside normalized semantics. *)
type source_info = {
  assumes : ltl list;
  guarantees : ltl list;
  user_invariants : invariant_user list;
  state_invariants : invariant_state_rel list;
}

(** Transition view for the raw proof-obligation pipeline stage. *)
type raw_transition = {
  src_state : ident;
  dst_state : ident;
  guard : Fo_formula.t;
  guard_iexpr : iexpr option;
  body_stmts : stmt list;
}

(** Raw node used by proof-obligation generation before contract injection. *)
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

(** Transition after contract injection, still before [pre_k] lowering. *)
type annotated_transition = {
  raw : raw_transition;
  requires : contract_formula list;
  ensures : contract_formula list;
}

(** Annotated node before [pre_k] elimination/lowering. *)
type annotated_node = {
  raw : raw_node;
  transitions : annotated_transition list;
  coherency_goals : contract_formula list;
  user_invariants : invariant_user list;
}

(** Transition ready for VC generation after [pre_k] lowering. *)
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

(** Verified node snapshot used by proof-obligation exports. *)
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

(** Optional snapshots of the proof-obligation pipeline. *)
type proof_views = {
  raw : raw_node option;
  annotated : annotated_node option;
  verified : verified_node option;
}

(** Program-level metadata attached to normalized contracts. *)
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

(** Forget normalized metadata and recover a source node. *)
val to_ast_node : node -> Ast.node

(** Build a contract formula with a fresh provenance id. *)
val with_origin : ?loc:loc -> Formula_origin.t -> ltl -> contract_formula

(** Extract the raw logical formulas carried by a list of normalized contract
    formulas. *)
val values : contract_formula list -> ltl list

(** Recompute [safe_*] summary fields from [cases], preserving explicitly set
    summary fields when they are still consistent with available safe cases. *)
val refresh_safe_summary : product_contract -> product_contract

(** Empty proof-view container (no raw/annotated/verified snapshots). *)
val empty_proof_views : proof_views
