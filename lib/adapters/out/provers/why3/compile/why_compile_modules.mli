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

(** Assembly of already-built Why3 declarations into node modules. *)

type spec_groups = { pre_labels : string list; post_labels : string list }

type program_ast = {
  mlw : Why3.Ptree.mlw_file;
  module_info : (string * spec_groups) list;
}

type module_unit =
  Why3.Ptree.ident
  * Why3.Ptree.qualid option
  * Why3.Ptree.decl list
  * spec_groups

val empty_groups : unit -> spec_groups
val common_module_name : string -> string
val import_module : string -> Why3.Ptree.decl

val assemble_node_modules :
  module_name:string ->
  imports:Why3.Ptree.decl list ->
  common_module_name:string ->
  common_import:Why3.Ptree.decl ->
  common_decls:Why3.Ptree.decl list ->
  shared_pre_bundle_modules:module_unit list ->
  shared_post_bundle_modules:module_unit list ->
  init_goal_decls:Why3.Ptree.decl list ->
  kernel_step_helper_units:Why_compile_product_helpers.helper_unit list ->
  module_unit list

val program_ast_of_modules : module_unit list -> program_ast
