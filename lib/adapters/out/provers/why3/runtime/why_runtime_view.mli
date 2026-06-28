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

(** Why3-specific intermediate representation of a Kairos node.

    Projects the grouped {!Step_contract_projection} view into the structured
    view consumed by Why3 compilation. The canonical contracts are owned by
    {!Canonical_obligations}; this module owns backend choices such as body
    slicing and final grouping, but it must not decide which product-step
    contracts logically exist. *)

open Core_syntax

type port_view = Why_runtime_view_types.port_view = {
  port_name : ident;
  port_type : ty;
}
(** An input, output or local variable port. *)

type runtime_action_view =
  Why_runtime_view_types.runtime_action_view =
  | ActionAssign of ident * expr
  | ActionAssert of hexpr
  | ActionIf of expr * runtime_action_view list * runtime_action_view list
  | ActionWhile of expr * hexpr list * expr option * runtime_action_view list
  | ActionMatch of
      expr * (ident * runtime_action_view list) list * runtime_action_view list
  | ActionSkip
(** An imperative action in the body of a transition. *)

type action_block_kind = Why_runtime_view_types.action_block_kind = ActionUser
(** Category of an action block. *)

type action_block_view = Why_runtime_view_types.action_block_view = {
  block_kind : action_block_kind;
  block_actions : runtime_action_view list;
}
(** A group of homogeneous actions within a transition. *)

type runtime_transition_view =
  Why_runtime_view_types.runtime_transition_view = {
  transition_id : string;
  src_state : ident;
  dst_state : ident;
  guard : expr option;
  requires : Ir.summary_formula list;
  ensures : Ir.summary_formula list;
  body : Core_syntax.stmt list;
  action_blocks : action_block_view list;
}
(** Full view of a source-program transition. *)

type runtime_step_class =
  Why_runtime_view_types.runtime_step_class =
  | StepSafe
  | StepBadGuarantee
(** Classification of a product transition. *)

type runtime_product_transition_view =
  Why_runtime_view_types.runtime_product_transition_view = {
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
  elaboration_checks : Ir.summary_formula list;
  forbidden : Ir.summary_formula list;
}
(** View of a transition in the synchronized product. *)

type t = Why_runtime_view_types.t = {
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
(** Complete view of a node, ready to be compiled to WhyML. *)

val transition_of_product_step :
  ?simplify_runtime_actions:bool ->
  runtime_product_transition_view ->
  runtime_transition_view
(** Projects a product transition to a plain transition by dropping relational
    information, used to compile its imperative body. *)

val of_ir_node :
  ?simplify_runtime_actions:bool ->
  ?slice_transition_bodies:bool ->
  Ir.node_ir ->
  t
(** Main entry point: builds the runtime view of a node from its IR. *)
