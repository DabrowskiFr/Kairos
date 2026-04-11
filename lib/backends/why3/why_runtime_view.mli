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

    Reconstructs from an {!Ir.node_ir} a structured view exposing ports,
    transitions (with guards, bodies and contracts), state-indexed branches,
    global contracts and user invariants. All compilation and contract-building
    modules in the backend consume this representation rather than the generic
    IR. *)

open Core_syntax

(** An input, output or local variable port. *)
type port_view = {
  port_name : ident;
  port_type : ty;
}

(** An imperative action in the body of a transition. *)
type runtime_action_view =
  | ActionAssign of ident * expr
      (** Simple assignment [x := e]. *)
  | ActionIf of expr * runtime_action_view list * runtime_action_view list
      (** Conditional branch. *)
  | ActionMatch of expr * (ident * runtime_action_view list) list * runtime_action_view list
      (** Constructor match. *)
  | ActionSkip
      (** No-op action. *)

(** Category of an action block. *)
type action_block_kind =
  | ActionUser
      (** Block corresponding to user-written code. *)

(** A group of homogeneous actions within a transition. *)
type action_block_view = {
  block_kind : action_block_kind;
  block_actions : runtime_action_view list;
}

(** Full view of a source-program transition. *)
type runtime_transition_view = {
  transition_id : string;
      (** Unique transition identifier. *)
  src_state : ident;
      (** Source control state. *)
  dst_state : ident;
      (** Target control state. *)
  guard : expr option;
      (** Triggering condition, or [None] if unconditional. *)
  requires : Ir.summary_formula list;
      (** Preconditions from the IR. *)
  ensures : Ir.summary_formula list;
      (** Postconditions from the IR. *)
  body : Ast.stmt list;
      (** Raw transition body (list of statements). *)
  action_blocks : action_block_view list;
      (** Structured body as typed action blocks. *)
}

(** Classification of a product transition with respect to guarantee violation. *)
type runtime_step_class =
  | StepSafe
      (** The transition does not violate any guarantee. *)
  | StepBadGuarantee
      (** The transition is allowed to violate a guarantee (worst-case assumption). *)

(** View of a transition in the program-times-monitor product (relational mode). *)
type runtime_product_transition_view = {
  transition_id : string;
  src_state : ident;
  dst_state : ident;
  guard : expr option;
  body : Ast.stmt list;
  step_class : runtime_step_class;
  product_src : Ir.product_state;
      (** Source product state (program state x guarantee state). *)
  product_dst : Ir.product_state;
      (** Target product state. *)
  requires : Ir.summary_formula list;
  propagates : Ir.summary_formula list;
      (** Formulas propagated from the previous state. *)
  ensures : Ir.summary_formula list;
  forbidden : Ir.summary_formula list;
      (** Formulas whose verification is intentionally deferred. *)
}

(** Transitions sharing the same source control state, grouped for helper
    generation in {!Why_compile}. *)
type transition_group_view = {
  group_state : ident;
  group_transitions : runtime_transition_view list;
}

(** One arm of the pattern match on the current control state in [step]. *)
type state_branch_view = {
  branch_state : ident;
  branch_transitions : runtime_transition_view list;
}

(** Complete view of a node, ready to be compiled to WhyML. *)
type t = {
  node_name : ident;
  inputs : port_view list;
  outputs : port_view list;
  locals : port_view list;
  control_states : ident list;
  init_control_state : ident;
      (** Initial control state (used for coherency goals). *)
  transitions : runtime_transition_view list;
  product_transitions : runtime_product_transition_view list;
  transition_groups : transition_group_view list;
  state_branches : state_branch_view list;
  assumes : ltl list;
  guarantees : ltl list;
  init_invariant_goals : Ir.summary_formula list;
      (** Formulas to check at the initial state (coherency goals). *)
}

(** Reconstructs an {!Ast.transition} from a transition view,
    giving access to generic AST accessors. *)
val transition_to_ast : runtime_transition_view -> Ast.transition

(** Reconstructs a full {!Ast.node} from the node view,
    used by {!Why_compile} to access semantic metadata. *)
val to_ast_node : t -> Ast.node

(** Projects a product transition to a plain transition by dropping relational
    information, used to compile its imperative body. *)
val transition_of_product_step : runtime_product_transition_view -> runtime_transition_view

(** Main entry point: builds the runtime view of a node from its IR. *)
val of_ir_node : Ir.node_ir -> t
