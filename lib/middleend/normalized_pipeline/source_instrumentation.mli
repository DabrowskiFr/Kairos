open Ast

val state_ctor : int -> string

val instrumentation_update_stmts :
  (ident * iexpr) list ->
  Ast.ltl list ->
  Spot_automaton.transition list ->
  stmt list

val instrumentation_assert : int -> stmt list

val inline_fo_atoms : (ident * iexpr) list -> fo -> fo

val finalize_instrumented_node :
  atom_map_exprs:(ident * iexpr) list ->
  user_assumes:ltl list ->
  user_guarantees:ltl list ->
  invariants_user:invariant_user list ->
  invariants_state_rel:invariant_state_rel list ->
  Ast.node ->
  trans:Normalized_program.transition list ->
  Ast.node
