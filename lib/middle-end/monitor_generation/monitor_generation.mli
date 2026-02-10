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

(** Concrete automaton type returned by the engine. *)
type monitor_generation_automaton = Automaton_engine.automaton

(** Full build artifact for a node: atoms, spec, and automaton. *)
type monitor_generation_build = {
  atoms: Monitor_generation_atoms.monitor_generation_atoms;
  atom_names: Ast.ident list;
  spec: Ast.fo_ltl;
  automaton: monitor_generation_automaton;
}

(** Build, minimize, and group the monitor residual automaton. *)
val build_monitor_automaton :
  atom_map:(Ast.fo * Ast.ident) list ->
  atom_names:Ast.ident list ->
  Ast.fo_ltl -> monitor_generation_automaton

(** Collect monitor atoms, build the monitor spec, and construct the automaton. *)
val build_monitor_for_node : Ast.node -> monitor_generation_build
