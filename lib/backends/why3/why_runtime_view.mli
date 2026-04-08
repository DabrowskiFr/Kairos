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

type runtime_action_view =
  | ActionAssign of Ast.ident * Ast.iexpr
  | ActionIf of Ast.iexpr * runtime_action_view list * runtime_action_view list
  | ActionMatch of Ast.iexpr * (Ast.ident * runtime_action_view list) list * runtime_action_view list
  | ActionSkip

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
  requires : Ir.summary_formula list;
  ensures : Ir.summary_formula list;
  body : Ast.stmt list;
  action_blocks : action_block_view list;
}

type runtime_step_class =
  | StepSafe
  | StepBadGuarantee

type runtime_product_transition_view = {
  transition_id : string;
  src_state : Ast.ident;
  dst_state : Ast.ident;
  guard : Ast.iexpr option;
  body : Ast.stmt list;
  step_class : runtime_step_class;
  product_src : Ir.product_state;
  product_dst : Ir.product_state;
  requires : Ir.summary_formula list;
  propagates : Ir.summary_formula list;
  ensures : Ir.summary_formula list;
  forbidden : Ir.summary_formula list;
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
  control_states : Ast.ident list;
  init_control_state : Ast.ident;
  transitions : runtime_transition_view list;
  product_transitions : runtime_product_transition_view list;
  transition_groups : transition_group_view list;
  state_branches : state_branch_view list;
  assumes : Ast.ltl list;
  guarantees : Ast.ltl list;
  user_invariants : Ast.invariant_user list;
  init_invariant_goals : Ir.summary_formula list;
}

val of_node :
  nodes:Ast.node list ->
  Ast.node ->
  t
val transition_to_ast : runtime_transition_view -> Ast.transition
val to_ast_node : t -> Ast.node

val transition_of_product_step : runtime_product_transition_view -> runtime_transition_view

val of_ir_node : Ir.node_ir -> t
