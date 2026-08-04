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

(** One outgoing monitor successor. Its source state is supplied by the
    containing {!product_prefix}; only the varying destination and guard are
    stored. *)
type monitor_successor = {
  destination_state_index : int;
  guard : Core_syntax.historical Core_syntax.hexpr;
}

(** One enabled program–assumption prefix from a reachable product source.

    The program transition determines the program source and destination. The
    assumption successor determines the assumption destination, while both
    monitor source states are stored once by the prefix. Guarantee successors
    contain only their varying destination and guard.

    An empty [guarantee_successors] list represents total guarantee blocking;
    conditional blocking is represented by incomplete coverage of their
    guards. *)
type product_prefix = {
  prog_transition : Verification_model.program_step;
  assume_source_state_index : int;
  assume_successor : monitor_successor;
  guarantee_source_state_index : int;
  guarantee_successors : monitor_successor list;
}

(** Reachable fragment of the explicit product for one program node. *)
type exploration = {
  (** Initial product state [(P_init, A0, G0)]. *)
  initial_state : product_state;
  (** Program–assumption prefixes together with their guarantee successors. *)
  prefixes : product_prefix list;
}

(** [prefix_source prefix] derives the product source from the program
    transition and the two monitor source states stored by [prefix]. *)
val prefix_source : product_prefix -> product_state

(** [successor_destination prefix successor] derives the complete product
    destination associated with one guarantee successor of [prefix]. *)
val successor_destination :
  product_prefix -> monitor_successor -> product_state

(** [program_guard prefix] derives the normalized first-order program guard
    from the unique program transition stored by [prefix]. *)
val program_guard :
  product_prefix ->
  Core_syntax.historical Core_syntax.hexpr

(** [states exploration] derives the normalized reachable-state list from the
    initial state, prefix sources and guarantee-successor destinations. *)
val states : exploration -> product_state list

(** [step_count exploration] counts the product triples represented by all
    guarantee successors. *)
val step_count : exploration -> int

(** [compare_state] service entrypoint. *)

val compare_state : product_state -> product_state -> int
(** Total order on product states, used to normalize rendered and exported
    state lists. *)
