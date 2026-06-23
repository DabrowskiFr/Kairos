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
    formula sharing, contracts, product-step helpers, initial goals, and final
    module assembly. *)

type spec_groups = Why_compile_modules.spec_groups = {
  pre_labels : string list;
  post_labels : string list;
}

type program_ast = Why_compile_modules.program_ast = {
  mlw : Why3.Ptree.mlw_file;
  module_info : (string * spec_groups) list;
}

open Why3
module Formula_sharing = Why_compile_formula_sharing
module Init_goals = Why_compile_init_goals
module Modules = Why_compile_modules
module Node_common = Why_compile_node_common
module Product_pipeline = Why_compile_product_pipeline

type env_info = Node_common.t

(* Shared compilation core: all node-specific data is read from [info.runtime_view].
   The active path builds [info] from the IR via [prepare_ir_node]. *)
(** [compile_node_with_info] helper value. *)

let compile_node_with_info ?(share_why3_facts = true)
    ?(simplify_why3_formulas = true) ?(simplify_why3_runtime_actions = true)
    ?(deduplicate_why3_terms = true) ?(group_why3_product_steps = true)
    ?(why3_product_step_group_max_cost = 0) (info : env_info) :
    (Ptree.ident * Ptree.qualid option * Ptree.decl list * spec_groups) list =
  let runtime_view = info.runtime_view in
  let module_name = info.module_name in
  let imports = info.imports in
  let common_module_name = info.common_module_name in
  let common_import = info.common_import in
  let env = info.env in
  let inputs = info.inputs in
  let formula_sharing =
    Formula_sharing.build
      { env; inputs; runtime_view; share_why3_facts }
  in
  let contracts =
    Why_contracts.build_contracts
      ~abstract_formula:formula_sharing.abstract_formula
      ~local_cut_candidate:formula_sharing.local_cut_candidate ~env:info.env
      ~runtime:runtime_view
      ~simplify_formulas:simplify_why3_formulas
      ~deduplicate_terms:deduplicate_why3_terms
  in
  let step_contracts =
    match contracts.step_contracts with
    | [] ->
        invalid_arg
          (Printf.sprintf
             "Why3 backend requires product-step contracts for node %s; the \
              reference-product pipeline produced no product transitions"
             runtime_view.node_name)
    | step_contracts -> step_contracts
  in
  let product_pipeline_context : Product_pipeline.context =
    {
      runtime_view;
      module_name;
      imports;
      common_import;
      env;
      inputs;
      share_why3_facts;
      simplify_why3_formulas;
      group_why3_product_steps;
      why3_product_step_group_max_cost;
      simplify_why3_runtime_actions;
      abstract_formula = formula_sharing.abstract_formula;
      abstract_formula_with_rec = formula_sharing.abstract_formula_with_rec;
      shared_formula_names_in_terms =
        formula_sharing.shared_formula_names_in_terms;
      local_shared_formula_decls = formula_sharing.local_shared_formula_decls;
    }
  in
  let product_pipeline =
    Product_pipeline.build product_pipeline_context step_contracts
  in

  let init_goal_decls = Init_goals.build { env; inputs; runtime_view } in

  Modules.assemble_node_modules ~module_name ~imports ~common_module_name
    ~common_import ~common_decls:info.common_decls
    ~shared_pre_bundle_modules:product_pipeline.shared_pre_bundle_modules
    ~shared_post_bundle_modules:product_pipeline.shared_post_bundle_modules
    ~init_goal_decls
    ~kernel_step_helper_units:product_pipeline.kernel_step_helper_units

(** [compile_node_from_ir_node] helper value. *)

let compile_node_from_ir_node ?(share_why3_facts = true)
    ?(simplify_why3_formulas = true) ?(slice_why3_transition_bodies = true)
    ?(simplify_why3_runtime_actions = true) ?(deduplicate_why3_terms = true)
    ?(group_why3_product_steps = true) ?(why3_product_step_group_max_cost = 0)
    (node : Ir.node_ir) :
    (Ptree.ident * Ptree.qualid option * Ptree.decl list * spec_groups) list =
  compile_node_with_info ~share_why3_facts ~simplify_why3_formulas
    ~simplify_why3_runtime_actions ~deduplicate_why3_terms
    ~group_why3_product_steps ~why3_product_step_group_max_cost
    (Node_common.prepare_ir_node ~simplify_why3_runtime_actions
       ~slice_why3_transition_bodies node)

(** [compile_program_ast_from_ir_nodes] helper value. *)

let compile_program_ast_from_ir_nodes ?(share_why3_facts = true)
    ?(simplify_why3_formulas = true) ?(slice_why3_transition_bodies = true)
    ?(simplify_why3_runtime_actions = true) ?(deduplicate_why3_terms = true)
    ?(group_why3_product_steps = true) ?(why3_product_step_group_max_cost = 0)
    (program_nodes : Ir.node_ir list) : program_ast =
  let modules =
    List.concat_map
      (compile_node_from_ir_node ~share_why3_facts ~simplify_why3_formulas
         ~slice_why3_transition_bodies ~simplify_why3_runtime_actions
         ~deduplicate_why3_terms ~group_why3_product_steps
         ~why3_product_step_group_max_cost)
      program_nodes
  in
  Modules.program_ast_of_modules modules
