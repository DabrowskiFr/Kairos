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
type module_unit = Ptree.ident * Ptree.decl list

let common_module_name module_name = module_name ^ "__Common"

let node_module name decls : module_unit = (ident name, decls)

let assemble_node_modules ~(module_name : string) ~(imports : Ptree.decl list)
    ~(common_module_name : string) ~(common_import : Ptree.decl)
    ~(common_decls : Ptree.decl list)
    ~(shared_formula_modules : module_unit list)
    ~(shared_post_modules : module_unit list)
    ~(kernel_step_helper_units : Why_compile_product_helpers.helper_unit list) =
  let common_module = node_module common_module_name common_decls in
  let helper_modules =
    kernel_step_helper_units
    |> List.map (fun (helper : Why_compile_product_helpers.helper_unit) ->
        node_module
          (module_name ^ "__" ^ helper.helper_name)
          (imports @ [ common_import ] @ helper.decls))
  in
  common_module
  :: (shared_formula_modules @ shared_post_modules @ helper_modules)
