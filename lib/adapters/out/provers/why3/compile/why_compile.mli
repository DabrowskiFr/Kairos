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

type spec_groups = Why_compile_modules.spec_groups = {
  pre_labels : string list;
  post_labels : string list;
}

type program_ast = Why_compile_modules.program_ast = {
  mlw : Why3.Ptree.mlw_file;
  module_info : (string * spec_groups) list;
}

val product_step_helper_name :
  index:int -> Why_runtime_view.runtime_product_transition_view -> string

val product_step_group_helper_name :
  index:int -> Why_runtime_view.runtime_product_transition_view -> string

val compile_program_ast_from_ir_nodes :
  ?share_why3_facts:bool ->
  ?simplify_why3_formulas:bool ->
  ?slice_why3_transition_bodies:bool ->
  ?simplify_why3_runtime_actions:bool ->
  ?deduplicate_why3_terms:bool ->
  ?group_why3_product_steps:bool ->
  ?why3_product_step_group_max_cost:int ->
  Ir.node_ir list ->
  program_ast
