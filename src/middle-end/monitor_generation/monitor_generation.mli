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

type monitor_generation_automaton = {
  states_raw: Ast.fo_ltl list;
  transitions_raw: Automaton_core.guarded_transition list;
  states: Ast.fo_ltl list;
  transitions: Automaton_core.guarded_transition list;
  grouped: Automaton_core.guarded_transition list;
}

type monitor_generation_build = {
  atoms: Monitor_generation_atoms.monitor_generation_atoms;
  atom_names: Ast.ident list;
  spec: Ast.fo_ltl;
  automaton: monitor_generation_automaton;
}

val build_monitor_automaton :
  atom_map:(Ast.fo * Ast.ident) list ->
  atom_names:Ast.ident list ->
  Ast.fo_ltl -> monitor_generation_automaton
(** Build, minimize, and group the monitor residual automaton. *)

val build_monitor_for_node : Ast.node -> monitor_generation_build
(** Collect monitor atoms, build the monitor spec, and construct the automaton. *)
