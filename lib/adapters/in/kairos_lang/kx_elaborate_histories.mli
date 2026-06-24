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
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *---------------------------------------------------------------------------*)

(** Generated-history elaboration.

    Histories are expanded at the surface level into ghost declarations,
    transition updates, and transition-local ensures before the final AST
    lowering pass. *)

type generated_history

val collect_node_histories :
  Kx_elaborate_env.env ->
  Kx_surface_syntax.node ->
  Kx_surface_syntax.contract_item list ->
  generated_history list

val history_ghosts : generated_history list -> Kx_surface_syntax.raw_vdecl list

val expand_histories_in_transition :
  input_names:Kx_core_syntax.ident list ->
  init_state:Kx_core_syntax.ident ->
  generated_history list ->
  Kx_surface_syntax.transition ->
  Kx_surface_syntax.transition
