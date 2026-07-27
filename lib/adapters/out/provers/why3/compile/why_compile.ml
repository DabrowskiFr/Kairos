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

(** Main WhyML compiler from canonical IR.

    This module orchestrates the Why3 backend for a node: common declarations,
    contracts, product-step helpers, initial goals, and final module assembly. *)

open Why3
module Bundles = Why_compile_bundles
module Modules = Why_compile_modules
module Node_common = Why_compile_node_common
module Product_helpers = Why_compile_product_helpers
module Product_plan = Why_compile_product_groups
module Ptree_helpers = Why_compile_ptree_helpers

let compile_node ?(group_why3_product_steps = true)
    (node : Core_syntax.history_free Ir.node_ir)
    (step_projection : Step_contract_projection.t) :
    Modules.module_unit list =
  let info = Node_common.prepare_ir_node node in
  let module_name = info.module_name in
  let imports = info.imports in
  let common_module_name = Modules.common_module_name module_name in
  let common_import = Ptree_helpers.import_module common_module_name in
  let env = info.env in
  let inputs = info.inputs in
  let step_contracts =
    match step_projection.step_contracts with
    | [] ->
        invalid_arg
          (Printf.sprintf
             "Why3 backend requires product-step contracts for node %s; the \
              reference-product pipeline produced no product transitions"
             node.semantics.sem_nname)
    | step_contracts -> step_contracts
  in
  let formula_sharing =
    Why_compile_formula_sharing.build ~env ~inputs
      step_projection.formula_index
  in
  let shared_formula_modules =
    Why_compile_formula_sharing.definition_modules formula_sharing
      ~module_name ~imports ~common_import
  in
  let formula_imports =
    Why_compile_formula_sharing.imports_for formula_sharing ~module_name
  in
  let bundles =
    Bundles.create ~module_name ~imports ~common_import ~inputs
      ~formula_imports
  in
  let helper_plan =
    Product_plan.build ~env ~formula_sharing ~group_why3_product_steps
      step_contracts
  in
  let helper_units =
    Product_helpers.kernel_step_helper_units ~env ~inputs ~formula_sharing
      ~formula_imports
      ~shared_post_call:(Bundles.shared_post_call bundles)
      helper_plan
  in
  let shared_post_modules = Bundles.shared_post_modules bundles in

  Modules.assemble_node_modules ~module_name ~imports ~common_module_name
    ~common_import ~common_decls:info.common_decls ~shared_formula_modules
    ~shared_post_modules ~kernel_step_helper_units:helper_units

let compile_program_ast ?(group_why3_product_steps = true)
    ~(nodes : Core_syntax.history_free Ir.node_ir list)
    ~(step_projections : Step_contract_projection.t list) () =
  let modules =
    List.map2
      (compile_node ~group_why3_product_steps)
      nodes step_projections
    |> List.concat
  in
  Ptree.Modules modules
