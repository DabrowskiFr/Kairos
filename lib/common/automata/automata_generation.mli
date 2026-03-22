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

(** Front-facing API for generating monitor automata from Kairos temporal
    contracts. *)

type automata_automaton = Spot_automaton.automaton
(* Concrete automaton type returned by the engine. *)

type automata_build = {
  atoms : Automata_atoms.automata_atoms;
  atom_names : Ast.ident list;
  spec : Ast.ltl;
  automaton : automata_automaton;
  assume_atoms : Automata_atoms.automata_atoms option;
  assume_atom_names : Ast.ident list;
  assume_spec : Ast.ltl option;
  assume_automaton : automata_automaton option;
}
(* Full build artifact for a node: atoms, spec, and automaton. *)

val build_monitor_automaton :
  atom_map:(Ast.fo * Ast.ident) list ->
  atom_names:Ast.ident list ->
  Ast.ltl ->
  automata_automaton
(* Build, minimize, and group the monitor residual automaton. *)

val build_monitor_spec : atom_map:(Ast.fo * Ast.ident) list -> Ast.node -> Ast.ltl
(* Build LTL monitor specification from a node (assumes/guarantees). *)

val build_assumption_spec : atom_map:(Ast.fo * Ast.ident) list -> Ast.node -> Ast.ltl
(* Build LTL spec made of node assumptions only. *)

val build_for_node : Ast.node -> automata_build
(* Collect monitor atoms, build the monitor spec, and construct the automaton. *)
