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

type guard = Fo_formula.t
type transition = int * guard * int

type automaton = {
  atom_names : Ast.ident list;
  states_raw : Ast.ltl list;
  transitions_raw : transition list;
  states : Ast.ltl list;
  transitions : transition list;
  grouped : transition list;
}

type automata_atoms = {
  atom_map : (Ast.fo_atom * Ast.ident) list;
  atom_named_exprs : (Ast.ident * Ast.iexpr) list;
}

type automata_build = {
  atoms : automata_atoms;
  guarantee_atom_names : Ast.ident list;
  guarantee_spec : Ast.ltl;
  guarantee_automaton : automaton;
  assume_atoms : automata_atoms option;
  assume_atom_names : Ast.ident list;
  assume_spec : Ast.ltl option;
  assume_automaton : automaton option;
}

type node_builds = (Ast.ident * automata_build) list
