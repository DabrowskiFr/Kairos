(** Intermediate-representation types shared by the refactored multi-pass
    backend. *)

(*---------------------------------------------------------------------------
 * Kairos — IR types for the refactored pipeline passes.
 *
 * Three layers, each the output of one pass:
 *   raw_node       — Pass 3: executable body, no Hoare triples
 *   annotated_node — Pass 4: Hoare triples added (prev^k x still present)
 *   verified_node  — Pass 5: history eliminated (prev^k x → __pre_k{k}_x)
 *---------------------------------------------------------------------------*)

(** {1 Pass 3 output — IR production}

    State machine + executable body.
    No requires/ensures: Hoare triples are computed in the next pass. *)

type raw_transition = {
  src_state            : Ast.ident;
  dst_state            : Ast.ident;
  guard                : Ast.ltl;
  (** Executable guard (imperative form), used to generate the Why3 match. *)
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
  (** Callee instances: [(instance_name, callee_node_name)]. *)
  instances     : (Ast.ident * Ast.ident) list;
  (** Map from history expressions (prev^k x) to their shift info. *)
  pre_k_map     : (Ast.hexpr * Temporal_support.pre_k_info) list;
  transitions   : raw_transition list;
  (** LTL specifications (used for contract generation in pass 4). *)
  assumes       : Ast.ltl list;
  guarantees    : Ast.ltl list;
}

(** {1 Pass 4 output — Triple computation}

    Hoare triples added to each transition.
    Formulas may still reference prev^k x (as [Ast.hexpr]);
    history elimination happens in pass 5. *)

type annotated_transition = {
  raw     : raw_transition;
  requires: Normalized_program.contract_formula list;
  ensures : Normalized_program.contract_formula list;
}

type annotated_node = {
  raw              : raw_node;
  transitions      : annotated_transition list;
  coherency_goals  : Normalized_program.contract_formula list;
  user_invariants  : Ast.invariant_user list;
  state_invariants : Ast.invariant_state_rel list;
}

(** {1 Pass 5 output — History elimination}

    All prev^k x references have been replaced by [IVar "__pre_k{k}_x"].
    Each transition carries the shift statements ([pre_k_updates]).
    The node locals include the introduced __pre_k{k}_x variables.
    This representation is ready for trivial structural Why3 emission. *)

type verified_transition = {
  src_state            : Ast.ident;
  dst_state            : Ast.ident;
  guard                : Ast.ltl;
  guard_iexpr          : Ast.iexpr option;
  body_stmts           : Ast.stmt list;
  (** Shift + capture statements: [__pre_k2_x := __pre_k1_x; __pre_k1_x := x]. *)
  pre_k_updates        : Ast.stmt list;
  (** Hoare triples, history-free. *)
  requires             : Normalized_program.contract_formula list;
  ensures              : Normalized_program.contract_formula list;
}

type verified_node = {
  node_name        : Ast.ident;
  inputs           : Ast.vdecl list;
  outputs          : Ast.vdecl list;
  (** Includes the introduced __pre_k{k}_x locals. *)
  locals           : Ast.vdecl list;
  control_states   : Ast.ident list;
  init_state       : Ast.ident;
  (** Callee instances: [(instance_name, callee_node_name)]. *)
  instances        : (Ast.ident * Ast.ident) list;
  transitions      : verified_transition list;
  assumes          : Ast.ltl list;
  guarantees       : Ast.ltl list;
  coherency_goals  : Normalized_program.contract_formula list;
  user_invariants  : Ast.invariant_user list;
  state_invariants : Ast.invariant_state_rel list;
}
