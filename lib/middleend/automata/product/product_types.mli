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

(** Core types for the explicit product explored by {!Product_build}. *)

open Core_syntax

(** One reachable state of the product automaton.

    A product state stores:
    - the current program control state;
    - the current state of the assumption automaton;
    - the current state of the guarantee automaton. *)
type product_state = {
  prog_state : ident;
  assume_state : int;
  guarantee_state : int;
}

(** Classification of an explicit product step according to its destination. *)
type step_class =
  | Safe
      (** The destination stays outside both bad automaton states. *)
  | Bad_assumption
      (** The destination reaches the bad assumption state. *)
  | Bad_guarantee
      (** The destination reaches the bad guarantee state while the assumption
          branch is still tracked explicitly. *)

(** Raw automaton edge used inside a product step. *)
type automaton_edge = Automaton_types.transition

(** One explicit step of the explored product.

    It records the exact local combination used during exploration:
    - one source and destination product state;
    - one program transition and its normalized first-order guard;
    - one assumption edge and its guard;
    - one guarantee edge and its guard;
    - the classification induced by the destination. *)
type product_step = {
  src : product_state;
  dst : product_state;
  prog_transition : Ir.transition;
  prog_guard : Fo_formula.t;
  assume_edge : automaton_edge;
  assume_guard : Fo_formula.t;
  guarantee_edge : automaton_edge;
  guarantee_guard : Fo_formula.t;
  step_class : step_class;
}

(** Reachable fragment of the explicit product for one program node. *)
type exploration = {
  (** Initial product state [(P_init, A0, G0)]. *)
  initial_state : product_state;
  (** Reachable product states discovered from {!initial_state}. *)
  states : product_state list;
  (** Explicit product steps between reachable states. *)
  steps : product_step list;
}

val compare_state : product_state -> product_state -> int
(** Total order on product states, used to normalize rendered and exported
    state lists. *)
