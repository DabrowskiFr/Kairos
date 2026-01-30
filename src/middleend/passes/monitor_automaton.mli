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

type monitor_automaton = {
  states_raw: Ast.ltl list;
  transitions_raw: Automaton_core.residual_transition list;
  states: Ast.ltl list;
  transitions: Automaton_core.residual_transition list;
  grouped: Automaton_core.guarded_transition list;
}

val build_monitor_automaton :
  atom_map:(Ast.fo * Ast.ident) list ->
  atom_names:Ast.ident list ->
  Ast.ltl -> monitor_automaton
(** Build, minimize, and group the monitor residual automaton. *)
