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

open Why3
open Why_compile_expr
open Why_compile_ptree_helpers

type spec_groups = { pre_labels : string list; post_labels : string list }

type program_ast = {
  mlw : Ptree.mlw_file;
  module_info : (string * spec_groups) list;
}

type module_unit =
  Ptree.ident * Ptree.qualid option * Ptree.decl list * spec_groups

let empty_groups () = { pre_labels = []; post_labels = [] }

let common_module_name module_name = module_name ^ "__Common"

let import_module name = Ptree.Duseimport (loc, false, [ (qid1 name, None) ])

let node_module name decls groups : module_unit =
  (ident name, None, decls, groups)

let contract_groups ~pre_labels ~post_labels = { pre_labels; post_labels }

let assemble_node_modules ~(use_product_helper_contracts : bool)
    ~(module_name : string) ~(imports : Ptree.decl list)
    ~(common_module_name : string) ~(common_import : Ptree.decl)
    ~(pre_labels : string list) ~(post_labels : string list)
    ~(common_decls : Ptree.decl list)
    ~(shared_formula_decls : Ptree.decl list)
    ~(shared_pre_bundle_modules : module_unit list)
    ~(shared_post_bundle_modules : module_unit list)
    ~(init_goal_decls : Ptree.decl list)
    ~(kernel_step_helper_units : (string * Ptree.decl list) list)
    ~(kernel_step_helper_decls : Ptree.decl list)
    ~(helper_decls : Ptree.decl list) ~(step_decl : Ptree.decl) =
  let groups = contract_groups ~pre_labels ~post_labels in
  if use_product_helper_contracts then
    let common_module = node_module common_module_name common_decls (empty_groups ()) in
    let init_modules =
      match init_goal_decls with
      | [] -> []
      | init_goals ->
          [
            node_module (module_name ^ "__init")
              (imports @ [ common_import ] @ init_goals)
              groups;
          ]
    in
    let helper_modules =
      kernel_step_helper_units
      |> List.map (fun (helper_name, decls) ->
             node_module (module_name ^ "__" ^ helper_name)
               (imports @ [ common_import ] @ decls)
               groups)
    in
    common_module
    :: (shared_pre_bundle_modules @ shared_post_bundle_modules @ init_modules
       @ helper_modules)
  else
    let decls =
      common_decls @ shared_formula_decls @ kernel_step_helper_decls @ helper_decls
      @ [ step_decl ] @ init_goal_decls
    in
    [ node_module module_name decls groups ]

let program_ast_of_modules modules =
  let mlw = Ptree.Modules (List.map (fun (id, _path, decls, _groups) -> (id, decls)) modules) in
  let module_info =
    List.map (fun (id, _path, _decls, groups) -> (id.Ptree.id_str, groups)) modules
  in
  { mlw; module_info }
