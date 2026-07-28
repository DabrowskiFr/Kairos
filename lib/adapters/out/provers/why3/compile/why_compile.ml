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

(** Mechanical WhyML translation of completed proof plans.

    Logical grouping, factorization, and sharing decisions are owned by
    {!Proof_plan}; this module only orders their Why3 representation and builds
    the compilation manifest. *)

open Why3
module Bundles = Why_compile_bundles
module Modules = Why_compile_modules
module Node_common = Why_compile_node_common
module Product_helpers = Why_compile_product_helpers
module Product_specs = Why_compile_product_specs
module Ptree_helpers = Why_compile_ptree_helpers

type compiled_obligation = {
  generated_symbol : string;
  source : string;
  node_name : string;
  transition : string;
  obligation_kind : string;
  obligation_family : string;
  obligation_category : string option;
}

type compilation = {
  ast : Why3.Ptree.mlw_file;
  manifest : compiled_obligation list;
}

type node_compilation = {
  modules : Modules.module_unit list;
  manifest : compiled_obligation list;
}

let product_state_source (state : Ir.product_state) =
  Printf.sprintf "(P=%s,A=%d,G=%d)" state.prog_state
    state.assume_state_index state.guarantee_state_index

let obligation_class
    (step_class : Step_contract_projection.step_class) =
  match step_class with
  | Step_contract_projection.StepSafe ->
      ("product-step-safe", Some "guarantee-progress")
  | Step_contract_projection.StepBadGuarantee ->
      ( "product-step-bad-guarantee",
        Some "guarantee-violation-exclusion" )

let transition_source (contract : Step_contract_projection.step_contract) =
  Printf.sprintf "%s -> %s (%s)" contract.program_step.src_state
    contract.program_step.dst_state contract.transition_id

let individual_manifest ~node_name ~generated_symbol
    (plan : Proof_plan.individual) =
  let contract = plan.member.contract in
  let obligation_kind, obligation_category =
    obligation_class contract.step_class
  in
  {
    generated_symbol;
    source =
      Printf.sprintf
        "helper=%s;partition=%s;product_src=%s;requires=%d;\
         local_requires=%d;ensures=%d;\
         elaboration_checks=%d;forbidden=%d"
        generated_symbol plan.member.partition_name
        (product_state_source contract.product_src)
        (List.length contract.requires)
        (List.length contract.runtime_requires)
        (List.length contract.ensures)
        (List.length contract.elaboration_checks)
        (List.length (Step_contract_projection.exclusions contract));
    node_name;
    transition = transition_source contract;
    obligation_kind;
    obligation_family = "product-step";
    obligation_category;
  }

let grouped_manifest ~node_name ~generated_symbol
    (plan : Proof_plan.grouped) =
  let contract = plan.representative.contract in
  let obligation_kind, obligation_category =
    obligation_class contract.step_class
  in
  {
    generated_symbol;
    source =
      Printf.sprintf
        "helper=%s;group_size=%d;partitions=%s;product_src=%s;requires=%d;\
         local_requires=%d;ensures=%d;\
         elaboration_checks=%d;forbidden=%d"
        generated_symbol (List.length plan.members)
        (plan.members
        |> List.map (fun member -> member.Proof_plan.partition_name)
        |> String.concat ",")
        (product_state_source contract.product_src)
        (List.length contract.requires)
        (List.length contract.runtime_requires)
        (List.length contract.ensures)
        (List.length contract.elaboration_checks)
        (List.length (Step_contract_projection.exclusions contract));
    node_name;
    transition = transition_source contract;
    obligation_kind;
    obligation_family = "product-step-group";
    obligation_category;
  }

let manifest_of_helper ~node_name plan
    (unit : Product_helpers.helper_unit) =
  match plan with
  | Proof_plan.Individual individual ->
      individual_manifest ~node_name ~generated_symbol:unit.helper_name
        individual
  | Proof_plan.Grouped grouped ->
      grouped_manifest ~node_name ~generated_symbol:unit.helper_name grouped

let compile_node (plan : Proof_plan.t) : node_compilation =
  let semantics = plan.semantics in
  let temporal_layout = plan.temporal_layout in
  let info = Node_common.prepare ~semantics ~temporal_layout in
  let module_name = info.module_name in
  let imports = info.imports in
  let common_module_name = Modules.common_module_name module_name in
  let common_import = Ptree_helpers.import_module common_module_name in
  let env = info.env in
  let inputs = info.inputs in
  let obligations = plan.obligations in
  let formula_sharing =
    Why_compile_formula_sharing.build ~env ~inputs
      plan.formula_index
  in
  let shared_formula_modules =
    Why_compile_formula_sharing.definition_modules formula_sharing
      ~module_name ~imports ~common_import
  in
  let formula_imports =
    Why_compile_formula_sharing.imports_for formula_sharing ~module_name
  in
  let bundles =
    Bundles.create ~module_name ~imports ~common_import ~env ~inputs
      ~formula_imports
      ~compile_conditions:
        (Product_specs.compile_conditions formula_sharing)
      plan.shared_postconditions
  in
  let helper_units =
    Product_helpers.kernel_step_helper_units ~env ~inputs ~formula_sharing
      ~formula_imports ~bundles obligations
  in
  let shared_post_modules = Bundles.shared_post_modules bundles in

  {
    modules =
      Modules.assemble_node_modules ~module_name ~imports
        ~common_module_name ~common_import ~common_decls:info.common_decls
        ~shared_formula_modules ~shared_post_modules
        ~kernel_step_helper_units:helper_units;
    manifest =
      List.map2
        (manifest_of_helper ~node_name:semantics.sem_nname)
        obligations helper_units;
  }

let compile_program_ast ~(proof_plans : Proof_plan.t list) () =
  let node_compilations =
    List.map compile_node proof_plans
  in
  {
    ast =
      Ptree.Modules
        (List.concat_map
           (fun compilation -> compilation.modules)
           node_compilations);
    manifest =
      List.concat_map
        (fun compilation -> compilation.manifest)
        node_compilations;
  }
