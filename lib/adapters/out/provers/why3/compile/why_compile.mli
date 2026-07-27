(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frederic Dabrowski
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

(** Public facade of the Why3 backend compiler.

    This module exposes only the entry points needed by the proof pipeline,
    renderer, and proof runner. Node-local construction details live in focused
    [Why_compile_*] modules and are intentionally kept out of this interface. *)

val compile_program_ast :
  ?group_why3_product_steps:bool ->
  nodes:Core_syntax.history_free Ir.node_ir list ->
  step_projections:Step_contract_projection.t list ->
  unit ->
  Why3.Ptree.mlw_file
