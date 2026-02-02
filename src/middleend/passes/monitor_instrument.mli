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

val monitor_state_ctor : int -> string
(** Monitor state constructor name for a given index (e.g. Mon0, Mon1). *)

type monitor_atoms_stage
(** Intermediate stage for monitor construction (atoms extracted/replaced). *)

val pass_atoms : Ast.node -> monitor_atoms_stage
(** FO -> atoms: extract atoms and replace them in the node. *)

val pass_build_automaton : monitor_atoms_stage -> Monitor_automaton.monitor_automaton
(** Build the monitor automaton from the atomized spec. *)

val pass_inline_atoms : monitor_atoms_stage -> Ast.node -> Ast.node
(** Atoms -> FO: inline atom variables back to formulas. *)

val transform_node : Ast.node -> Ast.node
(** Instrument a node with monitor support (standard compilation). *)

val transform_node_monitor : Ast.node -> Ast.node
(** Instrument a node with monitor support and preserve monitor details. *)
