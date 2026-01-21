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

(** {1 Residual Automaton} *)

val build_residual_graph :
  (Ast.fo * Ast.ident) list ->
  (string * bool) list list ->
  Ast.ltl ->
  Automaton_types.residual_state list * Automaton_types.residual_transition list
(** Build the residual automaton for an LTL formula. *)

val minimize_residual_graph :
  (string * bool) list list ->
  Automaton_types.residual_state list ->
  Automaton_types.residual_transition list ->
  Automaton_types.residual_state list * Automaton_types.residual_transition list
(** Minimize the residual automaton by partition refinement. *)

val group_transitions :
  Automaton_types.residual_transition list ->
  Automaton_types.grouped_transition list
(** Group transitions by (src,dst) and aggregate valuations. *)
