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

(** Front-facing API for generating guarantee/assumption automata from Kairos
    temporal contracts. *)

type automata_automaton = Automaton_types.automaton
type automata_build = Automaton_types.automata_build = {
  atoms : Automaton_types.automata_atoms;
  guarantee_atom_names : Ast.ident list;
  guarantee_spec : Ast.ltl;
  guarantee_automaton : automata_automaton;
  assume_atoms : Automaton_types.automata_atoms option;
  assume_atom_names : Ast.ident list;
  assume_spec : Ast.ltl option;
  assume_automaton : automata_automaton option;
}
type node_builds = (Ast.ident * automata_build) list

val build_guarantee_automaton :
  atom_map:(Ast.fo_atom * Ast.ident) list ->
  atom_named_exprs:(Ast.ident * Ast.iexpr) list ->
  atom_names:Ast.ident list ->
  Ast.ltl ->
  automata_automaton
(* Build, minimize, and group a guarantee automaton. *)

val build_guarantee_spec : atom_map:(Ast.fo_atom * Ast.ident) list -> Ast.node -> Ast.ltl
(* Build the LTL specification made of node guarantees. *)

val build_assumption_spec : atom_map:(Ast.fo_atom * Ast.ident) list -> Ast.node -> Ast.ltl
(* Build LTL spec made of node assumptions only. *)

val build_for_node : Ast.node -> automata_build
(* Collect atoms, build guarantee/assumption specs, and construct the
   corresponding automata. *)
