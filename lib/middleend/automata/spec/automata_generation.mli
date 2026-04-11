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
(** Public alias for the normalized automaton representation used downstream. *)
type automata_automaton = Automaton_types.automaton

(** Complete automata bundle built for one node. *)
type automata_build = Automaton_types.automata_build = {
  (** Atom table used for guarantee construction. *)
  atoms : Automaton_types.automata_atoms;
  (** Generated names of guarantee atoms, in backend order. *)
  guarantee_atom_names : ident list;
  (** Combined guarantee specification after frontend normalization. *)
  guarantee_spec : ltl;
  (** Guarantee automaton built from [guarantee_spec]. *)
  guarantee_automaton : automata_automaton;
  (** Optional atom table used for assumption construction. *)
  assume_atoms : Automaton_types.automata_atoms option;
  (** Generated names of assumption atoms, when assumptions are present. *)
  assume_atom_names : ident list;
  (** Combined assumption specification, when assumptions are present. *)
  assume_spec : ltl option;
  (** Assumption automaton, when assumptions are present. *)
  assume_automaton : automata_automaton option;
}

(** Automata bundles indexed by node name. *)
type node_builds = (ident * automata_build) list

val build_guarantee_automaton :
  atom_map:(fo_atom * ident) list ->
  atom_named_exprs:(ident * iexpr) list ->
  atom_names:ident list ->
  ltl ->
  automata_automaton
(** Build the automaton associated with one temporal specification.

    The function delegates to {!Automaton_build.build}, then returns the
    normalized automaton used by the rest of the middleend. *)

val build_guarantee_spec : atom_map:(fo_atom * ident) list -> Ast.node -> ltl
(** Combine the guarantees of a node into the monitor specification used for the
    guarantee automaton. Assumptions are included in this combined formula in
    the way required by the current monitor construction. *)

val build_assumption_spec : atom_map:(fo_atom * ident) list -> Ast.node -> ltl
(** Combine the assumptions of a node into a standalone assumption
    specification. *)

val build_for_node : Ast.node -> automata_build
(** Build the full automata bundle for one node:
    - collect guarantee atoms;
    - build the combined guarantee specification and automaton;
    - if assumptions exist, collect their atoms and build the corresponding
      assumption specification and automaton. *)
