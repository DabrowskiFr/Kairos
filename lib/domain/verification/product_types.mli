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
    - the current raw state of the deterministic assumption monitor;
    - the current raw state of the deterministic guarantee monitor. *)
type product_state = {
  prog_state : ident;
  assume_state_index : int;
  guarantee_state_index : int;
}

(** One explicit step of the explored product.

    It records the exact local combination used during exploration:
    - one source and destination product state;
    - one program transition and its normalized first-order guard;
    - the exact assumption post-image guard;
    - the exact guarantee post-image guard;
    A product step exists only when both partial monitors can advance. *)
type product_step = {
  src : product_state;
  dst : product_state;
  prog_transition : Verification_model.program_step;
  prog_guard : Core_syntax.historical Core_syntax.hexpr;
  assume_guard : Core_syntax.historical Core_syntax.hexpr;
  guarantee_guard : Core_syntax.historical Core_syntax.hexpr;
}

(** One enabled program–assumption prefix from a reachable product source.

    The guarantee post of this prefix is the list of {!product_step} values
    sharing these fields. An empty list represents total guarantee blocking;
    conditional blocking is represented by incomplete coverage of the step
    guards. *)
type product_prefix = {
  src : product_state;
  (** Raw assumption-monitor destination fixed by this prefix. *)
  assume_destination_state_index : int;
  prog_transition : Verification_model.program_step;
  prog_guard : Core_syntax.historical Core_syntax.hexpr;
  assume_guard : Core_syntax.historical Core_syntax.hexpr;
}

(** Reachable fragment of the explicit product for one program node. *)
type exploration = {
  (** Initial product state [(P_init, A0, G0)]. *)
  initial_state : product_state;
  (** Reachable product states discovered from {!initial_state}. *)
  states : product_state list;
  (** Explicit product steps between reachable states. *)
  steps : product_step list;
  (** Program–assumption prefixes, independently of guarantee progress. *)
  prefixes : product_prefix list;
}

(** [compare_state] service entrypoint. *)

val compare_state : product_state -> product_state -> int
(** Total order on product states, used to normalize rendered and exported
    state lists. *)
