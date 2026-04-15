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

(** Internal verification model shared by automata and IR construction.

    This model is intentionally distinct from the source-language AST.
    It stores only the semantics needed by middle-end verification passes. *)

open Core_syntax

(** Executable program step used by product and IR construction. *)
type program_step = {
  src_state : ident;
  dst_state : ident;
  guard_expr : expr option;
  body_stmts : stmt list;
}

(** State invariant attached to a control state. *)
type state_invariant = {
  state : ident;
  formula : hexpr;
}

(** Node-level verification model. *)
type node_model = {
  node_name : ident;
  inputs : vdecl list;
  outputs : vdecl list;
  locals : vdecl list;
  states : ident list;
  init_state : ident;
  steps : program_step list;
  assumes : ltl list;
  guarantees : ltl list;
  state_invariants : state_invariant list;
}

(** Program-level verification model. *)
type program_model = node_model list

(** Apply source-order priority semantics to transitions from each source state. *)
val prioritized_steps : program_step list -> program_step list

(** Apply transition prioritization to one node model. *)
val prioritize_node_steps : node_model -> node_model
