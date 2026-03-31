(** Shared type aliases used by IR-facing interfaces.

    This module provides a stable surface for common structural types used by
    the IR, while keeping compatibility with the current AST definitions. *)

type ident = Ast.ident
type loc = Ast.loc
type ltl = Ast.ltl
type ltl_o = Ast.ltl_o
type hexpr = Ast.hexpr
type iexpr = Ast.iexpr
type stmt = Ast.stmt
type vdecl = Ast.vdecl
type invariant_user = Ast.invariant_user
type invariant_state_rel = Ast.invariant_state_rel
type node_semantics = Ast.node_semantics
type transition = Ast.transition

(** Stable identifier attached to logical formulas across exports/reports. *)
type formula_id = int

(** Index of a transition inside a node transition table. *)
type transition_index = int

(** Index of an automaton state in generated assume/guarantee automata. *)
type automaton_state_index = int

(** Entry mapping a formula id to its optional origin metadata. *)
type formula_origin_entry = formula_id * Formula_origin.t option
