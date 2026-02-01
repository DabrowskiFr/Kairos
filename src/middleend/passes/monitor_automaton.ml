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
open Monitor_atoms
open Monitor_spec

type monitor_automaton = {
  states_raw: ltl list;
  transitions_raw: residual_transition list;
  states: ltl list;
  transitions: residual_transition list;
  grouped: guarded_transition list;
}

let build_monitor_automaton ~(atom_map:(fo * ident) list) ~(atom_names:ident list)
  (spec:ltl) : monitor_automaton =
  let valuations = enumerate_valuations atom_map atom_names in
  let states_raw, transitions_raw = build_residual_graph atom_map valuations spec in
  let states, transitions =
    minimize_residual_graph valuations states_raw transitions_raw
  in
  let grouped = group_transitions_bdd atom_names transitions in
  { states_raw; transitions_raw; states; transitions; grouped }

type monitor_build = {
  atoms: Monitor_atoms.monitor_atoms;
  atom_names: ident list;
  spec: ltl;
  automaton: monitor_automaton;
}

let build_monitor_for_node (n:node) : monitor_build =
  let atoms = collect_monitor_atoms n in
  let atom_names = List.map snd atoms.atom_map in
  let spec = build_monitor_spec ~atom_map:atoms.atom_map n in
  let automaton =
    build_monitor_automaton ~atom_map:atoms.atom_map ~atom_names spec
  in
  { atoms; atom_names; spec; automaton }
