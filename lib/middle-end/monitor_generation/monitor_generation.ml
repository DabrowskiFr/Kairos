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

open Ast
open Automaton_engine
open Monitor_generation_atoms
open Monitor_generation_spec

type monitor_generation_automaton = Automaton_engine.automaton

let build_monitor_automaton ~(atom_map : (fo * ident) list) ~(atom_names : ident list)
    (spec : fo_ltl) : monitor_generation_automaton =
  Automaton_engine.build ~atom_map ~atom_names spec

type monitor_generation_build = {
  atoms : Monitor_generation_atoms.monitor_generation_atoms;
  atom_names : ident list;
  spec : fo_ltl;
  automaton : monitor_generation_automaton;
  assume_atoms : Monitor_generation_atoms.monitor_generation_atoms option;
  assume_atom_names : ident list;
  assume_spec : fo_ltl option;
  assume_automaton : monitor_generation_automaton option;
}

let build_monitor_for_node (n : Ast.node) : monitor_generation_build =
  let atoms = collect_monitor_atoms n in
  let atom_names = List.map snd atoms.atom_map in
  let spec = build_monitor_spec ~atom_map:atoms.atom_map n in
  let automaton = build_monitor_automaton ~atom_map:atoms.atom_map ~atom_names spec in
  let assume_atoms, assume_atom_names, assume_spec, assume_automaton =
    if n.assumes = [] then (None, [], None, None)
    else
      let atoms_a = collect_monitor_atoms_from_ltls n ~ltls:n.assumes in
      let atom_names_a = List.map snd atoms_a.atom_map in
      let spec_a = build_assumption_spec ~atom_map:atoms_a.atom_map n in
      let automaton_a =
        build_monitor_automaton ~atom_map:atoms_a.atom_map ~atom_names:atom_names_a spec_a
      in
      (Some atoms_a, atom_names_a, Some spec_a, Some automaton_a)
  in
  {
    atoms;
    atom_names;
    spec;
    automaton;
    assume_atoms;
    assume_atom_names;
    assume_spec;
    assume_automaton;
  }
