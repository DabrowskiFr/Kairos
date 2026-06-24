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

(** Shared types for the Why3 runtime view. *)

open Core_syntax

type port_view = { port_name : ident; port_type : ty }

type runtime_action_view =
  | ActionAssign of ident * expr
  | ActionAssert of hexpr
  | ActionIf of expr * runtime_action_view list * runtime_action_view list
  | ActionWhile of expr * hexpr list * expr option * runtime_action_view list
  | ActionMatch of
      expr * (ident * runtime_action_view list) list * runtime_action_view list
  | ActionSkip

type action_block_kind = ActionUser

type action_block_view = {
  block_kind : action_block_kind;
  block_actions : runtime_action_view list;
}

type runtime_transition_view = {
  transition_id : string;
  src_state : ident;
  dst_state : ident;
  guard : expr option;
  requires : Ir.summary_formula list;
  ensures : Ir.summary_formula list;
  body : Core_syntax.stmt list;
  action_blocks : action_block_view list;
}

type runtime_step_class = StepSafe | StepBadGuarantee

type runtime_product_transition_view = {
  transition_id : string;
  src_state : ident;
  dst_state : ident;
  guard : expr option;
  body : Core_syntax.stmt list;
  step_class : runtime_step_class;
  product_src : Ir.product_state;
  product_dst : Ir.product_state;
  requires : Ir.summary_formula list;
  local_requires : Ir.summary_formula list;
  propagates : Ir.summary_formula list;
  ensures : Ir.summary_formula list;
  forbidden : Ir.summary_formula list;
}

type t = {
  node_name : ident;
  type_decls : enum_decl list;
  function_decls : pure_function_decl list;
  inputs : port_view list;
  outputs : port_view list;
  locals : port_view list;
  control_states : ident list;
  init_control_state : ident;
  product_transitions : runtime_product_transition_view list;
  assumes : ltl list;
  guarantees : ltl list;
  init_invariant_goals : Ir.summary_formula list;
}
