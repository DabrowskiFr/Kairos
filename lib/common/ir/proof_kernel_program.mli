(** Reactive program and explicit/fallback product construction for the kernel IR. *)

module Abs = Normalized_program
module PT = Product_types

val build_reactive_program :
  node_name:Ast.ident ->
  node:Abs.node ->
  Proof_kernel_types.reactive_program_ir

val build_automaton :
  role:Proof_kernel_types.automaton_role ->
  labels:string list ->
  bad_idx:int ->
  grouped_edges:PT.automaton_edge list ->
  atom_map_exprs:(Ast.ident * Ast.iexpr) list ->
  automaton_guard_fo:((Ast.ident * Ast.iexpr) list -> Spot_automaton.guard -> Ast.ltl) ->
  Proof_kernel_types.safety_automaton_ir

val is_feasible_product_step :
  node:Abs.node ->
  analysis:Product_build.analysis ->
  Proof_kernel_types.product_step_ir ->
  bool

val build_product_step :
  reactive_program:Proof_kernel_types.reactive_program_ir ->
  PT.product_step ->
  Proof_kernel_types.product_step_ir

val synthesize_fallback_product_steps :
  node:Abs.node ->
  analysis:Product_build.analysis ->
  reactive_program:Proof_kernel_types.reactive_program_ir ->
  live_states:PT.product_state list ->
  automaton_guard_fo:((Ast.ident * Ast.iexpr) list -> Spot_automaton.guard -> Ast.ltl) ->
  product_state_of_pt:(PT.product_state -> Proof_kernel_types.product_state_ir) ->
  product_step_kind_of_pt:(PT.step_class -> Proof_kernel_types.product_step_kind) ->
  is_live_state:(analysis:Product_build.analysis -> PT.product_state -> bool) ->
  Proof_kernel_types.product_step_ir list
