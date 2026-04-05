
open Ir_shared_types

type formula_meta = {
  origin : Formula_origin.t option;
  oid : formula_id;
  loc : loc option;
}

type contract_formula = {
  logic : Fo_formula.t;
  meta : formula_meta;
}

(** JSON encoding for [formula_meta], used by downstream derived encoders. *)
val formula_meta_to_yojson : formula_meta -> Yojson.Safe.t
(** JSON decoding for [formula_meta], used by downstream derived decoders. *)
val formula_meta_of_yojson : Yojson.Safe.t -> (formula_meta, string) result
(** JSON encoding for [contract_formula], used by proof/artifact schemas. *)
val contract_formula_to_yojson : contract_formula -> Yojson.Safe.t
(** JSON decoding for [contract_formula], used by proof/artifact schemas. *)
val contract_formula_of_yojson : Yojson.Safe.t -> (contract_formula, string) result

(** Reachable state in the synchronous product
    [(program state, assume automaton state, guarantee automaton state)]. *)
type product_state = {
  prog_state : ident;
  assume_state_index : automaton_state_index;
  guarantee_state_index : automaton_state_index;
}

(** Residual safe branch attached to a canonical product contract.

    Fields:
    {ul
    {- [product_dst_id]: stable destination identifier used by renderers;}
    {- [product_dst]: destination product state;}
    {- [guarantee_guard]: guarantee-side selector guard;}
    {- [propagates]: formulas propagated by this branch to the next step.
       In the current pipeline they are produced from safe guarantee guards
       (origin [GuaranteeAutomaton]) during [post], then consumed by [pre]:
       [pre] keeps those formulas, shifts them with
       [shift_ltl_forward_inputs], and injects the result into destination
       canonical [requires] with origin [GuaranteePropagation].}
    {- [ensures]: branch-specific postconditions.}} *)
type safe_product_case = {
  product_dst_id : string;
  product_dst : product_state;
  guarantee_guard : Fo_formula.t;
  propagates : contract_formula list;
  ensures : contract_formula list;
}

(** Residual unsafe branch attached to a canonical product contract.

    Fields:
    {ul
    {- [product_dst_id]: stable destination identifier used by renderers;}
    {- [product_dst]: destination product state;}
    {- [guarantee_guard]: guarantee-side selector guard;}
    {- [ensures]: branch-specific postconditions;}
    {- [forbidden]: forbidden formulas (typically bad-guarantee).}} *)
type unsafe_product_case = {
  product_dst_id : string;
  product_dst : product_state;
  guarantee_guard : Fo_formula.t;
  ensures : contract_formula list;
  forbidden : contract_formula list;
}

(** Identity shared by all product steps grouped in a canonical contract. *)
type product_contract_identity = {
  program_transition_index : transition_index;
  product_src_id : string;
  product_src : product_state;
  assume_guard : Fo_formula.t;
}

(** Contract formulas shared by all cases in a canonical contract. *)
type product_contract_common = {
  requires : contract_formula list;
  ensures : contract_formula list;
}

(** Precomputed safe summary consumed by proof/export backends. *)
type product_contract_safe_summary = {
  safe_destination_id : string option;
  safe_product_dsts : product_state list;
  safe_propagates : contract_formula list;
  safe_ensures : contract_formula list;
}

(** Canonical contract for a product-step group.

    A contract factors all steps sharing:
    {ul
    {- the same program transition;}
    {- the same product source;}
    {- the same assume guard.}}

    The [safe_*] fields store the already-computed safe summary consumed by the
    Why backend, while [safe_cases]/[unsafe_cases] keep branch-level details for
    diagnostics and exports.

    Fields:
    {ul
    {- [identity]: shared group identity;}
    {- [common]: formulas shared by all branches;}
    {- [safe_summary]: precomputed safe aggregation;}
    {- [safe_cases]: residual admissible branches;}
    {- [unsafe_cases]: residual branches to exclude.}}

    Invariant:
    [safe_summary] is the canonical aggregation of safe cases and is kept
    consistent by {!refresh_safe_summary}. *)
type product_contract = {
  identity : product_contract_identity;
  common : product_contract_common;
  safe_summary : product_contract_safe_summary;
  safe_cases : safe_product_case list;
  unsafe_cases : unsafe_product_case list;
}

(** Normalized transition.

    This record combines:
    {ul
    {- source control-flow information;}
    {- the executable statement body.}} *)
type transition = {
  src : ident;
  dst : ident;
  guard : iexpr option;
  body : stmt list;
}

type node_semantics = Ast.node_semantics

(** Source-level contractual information kept alongside normalized semantics.

    This data is preserved for traceability and export; it is not a duplicate
    of normalized transition contracts. *)
type source_info = {
  assumes : ltl list;
  guarantees : ltl list;
  user_invariants : invariant_user list;
  state_invariants : invariant_state_rel list;
}

(** Shared executable part of a transition, reused across proof phases.

    Fields:
    {ul
    {- [src_state]: source control state;}
    {- [dst_state]: destination control state;}
    {- [guard_iexpr]: source guard expression, when available;}
    {- [body_stmts]: executable statement list.}} *)
type transition_core = {
  src_state : ident;
  dst_state : ident;
  guard_iexpr : iexpr option;
  body_stmts : stmt list;
}

(** Shared contract payload attached to a transition in a proof phase.

    The same structure is reused by annotated and verified transitions to avoid
    phase-specific duplication of [requires]/[ensures] fields. *)
type transition_contracts = {
  requires : contract_formula list;
  ensures : contract_formula list;
}

(** Transition view for the raw proof-obligation pipeline stage. *)
type raw_transition = {
  core : transition_core;
  guard : Fo_formula.t;
}

(** Shared structural part of a node, reused across proof phases. *)
type node_core = {
  node_name : ident;
  inputs : vdecl list;
  outputs : vdecl list;
  locals : vdecl list;
  control_states : ident list;
  init_state : ident;
  instances : (ident * ident) list;
}

(** Raw node used by proof-obligation generation before contract injection. *)
type raw_node = {
  core : node_core;
  pre_k_map : (hexpr * Temporal_support.pre_k_info) list;
  transitions : raw_transition list;
  assumes : ltl list;
  guarantees : ltl list;
}

(** Transition after contract injection, still before [pre_k] lowering. *)
type annotated_transition = {
  raw : raw_transition;
  contracts : transition_contracts;
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
  core : transition_core;
  guard : Fo_formula.t;
  pre_k_updates : stmt list;
  contracts : transition_contracts;
}

(** Verified node snapshot used by proof-obligation exports. *)
type verified_node = {
  core : node_core;
  transitions : verified_transition list;
  product_transitions : product_contract list;
  assumes : ltl list;
  guarantees : ltl list;
  coherency_goals : contract_formula list;
  user_invariants : invariant_user list;
}

(** Optional snapshots of the proof-obligation pipeline.

    These are pipeline artifacts for diagnostics/export; the semantic source of
    truth remains [node] + product contracts. *)
type proof_views = {
  raw : raw_node option;
  annotated : annotated_node option;
  verified : verified_node option;
}

(** Program-level metadata attached to normalized contracts.

    [contract_origin_map] stores one entry per known formula id, allowing
    downstream tools to recover origin labels without re-walking the whole IR. *)
type contracts_info = {
  contract_origin_map : formula_origin_entry list;
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
val with_origin : ?loc:loc -> Formula_origin.t -> Fo_formula.t -> contract_formula

(** Extract the raw logical formulas carried by a list of normalized contract
    formulas.

    This helper intentionally drops metadata and keeps only [logic]. *)
val values : contract_formula list -> Fo_formula.t list

(** Recompute [safe_*] summary fields from [cases], preserving explicitly set
    summary fields when they are still consistent with available safe cases. *)
val refresh_safe_summary : product_contract -> product_contract

(** Empty proof-view container (no raw/annotated/verified snapshots). *)
val empty_proof_views : proof_views
