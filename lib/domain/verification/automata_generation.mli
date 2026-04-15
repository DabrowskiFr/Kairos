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

(** Front-facing API for generating assumption and guarantee automata from the
    temporal contracts attached to a node. *)
open Core_syntax
open Automaton_types
(** Public alias for the normalized automaton representation used downstream. *)
(* type automata_automaton = Automaton_types.automaton

(** Complete automata bundle built for one node. *)
type automata_build = Automaton_types.automata_build = {
  (** Guarantee automaton built from normalized ensures formulas. *)
  guarantee_automaton : automata_automaton;
  (** Assumption automaton. It is trivial ([true]-loop) when no requires are
      present. *)
  assume_automaton : automata_automaton;
} *)

type automata_info = {
  residual_state_count : int;
  residual_edge_count : int;
  warnings : string list;
}

val build_for_node :
  build_automaton:
    (atom_map:(ltl_atom * ident) list ->
    ltl ->
    automaton) ->
  Verification_model.node_model ->
  automata_spec
(** Build the full automata bundle for one node:
    - collect guarantee atoms;
    - build the guarantee automaton;
    - build the assumption automaton (trivial when no requires are present). *)

val run :
  Verification_model.program_model ->
  build_automaton:
    (atom_map:(ltl_atom * ident) list ->
    ltl ->
    automaton) ->
  (ident * automata_spec) list * automata_info
