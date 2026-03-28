(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *---------------------------------------------------------------------------*)

(** Reconstructs the executable runtime view consumed by Why generation. *)

type port_view = {
  port_name : Ast.ident;
  port_type : Ast.ty;
}

type instance_view = {
  instance_name : Ast.ident;
  callee_node_name : Ast.ident;
}

type callee_summary_view = {
  callee_node_name : Ast.ident;
  callee_inputs : port_view list;
  callee_outputs : port_view list;
  callee_locals : port_view list;
  callee_states : Ast.ident list;
  callee_input_names : Ast.ident list;
  callee_output_names : Ast.ident list;
  callee_user_invariants : Ast.invariant_user list;
  callee_contract : Kernel_guided_contract.exported_summary_contract;
}

type call_site_view = {
  call_instance : Ast.ident;
  call_args : Ast.iexpr list;
  call_outputs : Ast.ident list;
}

type runtime_action_view =
  | ActionAssign of Ast.ident * Ast.iexpr
  | ActionIf of Ast.iexpr * runtime_action_view list * runtime_action_view list
  | ActionMatch of Ast.iexpr * (Ast.ident * runtime_action_view list) list * runtime_action_view list
  | ActionSkip
  | ActionCall of call_site_view

type action_block_kind =
  | ActionUser

type action_block_view = {
  block_kind : action_block_kind;
  block_actions : runtime_action_view list;
}

type runtime_transition_view = {
  transition_id : string;
  src_state : Ast.ident;
  dst_state : Ast.ident;
  guard : Ast.iexpr option;
  requires : Ir.contract_formula list;
  ensures : Ir.contract_formula list;
  body : Ast.stmt list;
  action_blocks : action_block_view list;
  call_sites : call_site_view list;
}

type runtime_product_transition_view = {
  transition_id : string;
  src_state : Ast.ident;
  dst_state : Ast.ident;
  guard : Ast.iexpr option;
  step_class : Ir.product_step_class;
  product_src : Ir.product_state;
  product_dst : Ir.product_state;
  requires : Ir.contract_formula list;
  ensures : Ir.contract_formula list;
  forbidden : Ir.contract_formula list;
}

type transition_group_view = {
  group_state : Ast.ident;
  group_transitions : runtime_transition_view list;
}

type state_branch_view = {
  branch_state : Ast.ident;
  branch_transitions : runtime_transition_view list;
}

type t = {
  node_name : Ast.ident;
  inputs : port_view list;
  outputs : port_view list;
  locals : port_view list;
  instances : instance_view list;
  callee_summaries : callee_summary_view list;
  control_states : Ast.ident list;
  init_control_state : Ast.ident;
  transitions : runtime_transition_view list;
  product_transitions : runtime_product_transition_view list;
  transition_groups : transition_group_view list;
  state_branches : state_branch_view list;
  assumes : Ast.ltl list;
  guarantees : Ast.ltl list;
  user_invariants : Ast.invariant_user list;
  coherency_goals : Ir.contract_formula list;
}

val of_node :
  nodes:Ast.node list ->
  Ast.node ->
  t
val find_callee_summary : t -> Ast.ident -> callee_summary_view option
val transition_to_ast : runtime_transition_view -> Ast.transition
val to_ast_node : t -> Ast.node
val has_instance_calls : t -> bool

val of_ir_node :
  program_nodes:Ir.node list ->
  Ir.node ->
  t
