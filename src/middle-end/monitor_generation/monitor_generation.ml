(*---------------------------------------------------------------------------
 * Tempo - synchronous runtime for OCaml
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

open Ast
open Automaton_core
open Monitor_generation_atoms
open Monitor_generation_spec

type monitor_generation_automaton = {
  states_raw: fo_ltl list;
  transitions_raw: guarded_transition list;
  states: fo_ltl list;
  transitions: guarded_transition list;
  grouped: guarded_transition list;
}

let build_monitor_automaton ~(atom_map:(fo * ident) list) ~(atom_names:ident list)
  (spec:fo_ltl) : monitor_generation_automaton =
  let states_raw, transitions_raw =
    build_residual_graph_bdd ~atom_map ~atom_names spec
  in
  let states, transitions =
    minimize_residual_graph_bdd states_raw transitions_raw
  in
  { states_raw;
    transitions_raw;
    states;
    transitions;
    grouped = transitions; }

type monitor_generation_build = {
  atoms: Monitor_generation_atoms.monitor_generation_atoms;
  atom_names: ident list;
  spec: fo_ltl;
  automaton: monitor_generation_automaton;
}

let build_monitor_for_node (n:node) : monitor_generation_build =
  let atoms = collect_monitor_atoms n in
  let atom_names = List.map snd atoms.atom_map in
  let spec = build_monitor_spec ~atom_map:atoms.atom_map n in
  let automaton =
    build_monitor_automaton ~atom_map:atoms.atom_map ~atom_names spec
  in
  { atoms; atom_names; spec; automaton }
