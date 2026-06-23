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

    This module assembles Why3 module declarations (types, accessors, step
    helpers, contracts and goals) from {!Ir.node_ir} runtime views. *)

[@@@ocaml.warning "-8"]

type spec_groups = Why_compile_modules.spec_groups = {
  pre_labels : string list;
  post_labels : string list;
}

type program_ast = Why_compile_modules.program_ast = {
  mlw : Why3.Ptree.mlw_file;
  module_info : (string * spec_groups) list;
}

open Why3
open Ptree
open Core_syntax
open Pretty
open Pre_k_layout
open Why_compile_expr
open Why_compile_ptree_helpers
open Why_compile_logic
module Formula_sharing = Why_compile_formula_sharing
module Init_goals = Why_compile_init_goals
module Modules = Why_compile_modules
module Product_pipeline = Why_compile_product_pipeline
module Step_names = Why_compile_step_names

(** [why_type_name] maps source enum type names to WhyML type identifiers. WhyML
    type identifiers are lowercase, while Kairos examples commonly use CamelCase
    enum names. *)
let why_type_name name =
  if String.equal name "state" then "state"
  else "kairos_" ^ String.uncapitalize_ascii name

(** [module_name_of_node] helper value. *)

let module_name_of_node (name : Core_syntax.ident) : string =
  String.capitalize_ascii name

(** Type [env_info]. *)

type env_info = {
  runtime_view : Why_runtime_view.t;
  module_name : string;
  imports : Why3.Ptree.decl list;
  type_enum_decls : Why3.Ptree.decl list;
  type_state : Why3.Ptree.decl;
  type_vars : Why3.Ptree.decl;
  env : Why_compile_expr.env;
  inputs : Why3.Ptree.binder list;
}

(** [prepare_runtime_view] helper value. *)

let prepare_runtime_view ~(temporal_layout : Ir.temporal_layout)
    (runtime : Why_runtime_view.t) : env_info =
  let module_name = module_name_of_node runtime.node_name in
  let imports =
    [
      Ptree.Duseimport (loc, false, [ (qid1 "int.Int", None) ]);
      Ptree.Duseimport (loc, false, [ (qid1 "array.Array", None) ]);
    ]
  in
  let type_state =
    Ptree.Dtype
      [
        {
          td_loc = loc;
          td_ident = ident "state";
          td_params = [];
          td_vis = Public;
          td_mut = false;
          td_inv = [];
          td_wit = None;
          td_def =
            TDalgebraic
              (List.map (fun s -> (loc, ident s, [])) runtime.control_states);
        };
      ]
  in
  let type_enum_decls =
    runtime.type_decls
    |> List.map (fun (decl : enum_decl) ->
        Ptree.Dtype
          [
            {
              td_loc = loc;
              td_ident = ident (why_type_name decl.enum_name);
              td_params = [];
              td_vis = Public;
              td_mut = false;
              td_inv = [];
              td_wit = None;
              td_def =
                TDalgebraic
                  (List.map
                     (fun ctor -> (loc, ident ctor, []))
                     decl.enum_constructors);
            };
          ])
  in
  let pre_k_infos = temporal_layout in
  let inv_links = [] in
  let base_vars =
    "st"
    :: List.map
         (fun (p : Why_runtime_view.port_view) -> p.port_name)
         (runtime.locals @ runtime.outputs)
  in
  let env = { rec_name = "vars"; rec_vars = base_vars; links = inv_links } in
  let local_fields =
    List.map
      (fun v ->
        {
          f_loc = loc;
          f_ident = ident v.Why_runtime_view.port_name;
          f_pty = default_pty v.port_type;
          f_mutable = true;
          f_ghost = false;
        })
      runtime.locals
  in
  let output_fields =
    List.map
      (fun v ->
        {
          f_loc = loc;
          f_ident = ident v.Why_runtime_view.port_name;
          f_pty = default_pty v.port_type;
          f_mutable = true;
          f_ghost = false;
        })
      runtime.outputs
  in
  let fields : Ptree.field list =
    {
      f_loc = loc;
      f_ident = ident "st";
      f_pty = Ptree.PTtyapp (qid1 "state", []);
      f_mutable = true;
      f_ghost = false;
    }
    :: (local_fields @ output_fields)
  in
  let type_vars =
    Ptree.Dtype
      [
        {
          td_loc = loc;
          td_ident = ident "vars";
          td_params = [];
          td_vis = Public;
          td_mut = true;
          td_inv = [];
          td_wit = None;
          td_def = TDrecord fields;
        };
      ]
  in
  let vars_param =
    (loc, Some (ident "vars"), false, Some (Ptree.PTtyapp (qid1 "vars", [])))
  in
  let input_binders =
    List.map
      (fun (v : Why_runtime_view.port_view) ->
        (loc, Some (ident v.port_name), false, Some (default_pty v.port_type)))
      runtime.inputs
  in
  let pre_k_binders =
    let seen = Hashtbl.create 16 in
    pre_k_infos
    |> List.concat_map (fun (info : Pre_k_layout.pre_k_info) ->
        info.names
        |> List.filter_map (fun name ->
            if Hashtbl.mem seen name then None
            else (
              Hashtbl.add seen name ();
              Some (loc, Some (ident name), false, Some (default_pty info.vty)))))
  in
  let inputs = vars_param :: (input_binders @ pre_k_binders) in
  {
    runtime_view = runtime;
    module_name;
    imports;
    type_enum_decls;
    type_state;
    type_vars;
    env;
    inputs;
  }

(** [prepare_ir_node] helper value. *)

let prepare_ir_node ?(simplify_why3_runtime_actions = true)
    ?(slice_why3_transition_bodies = true) (node : Ir.node_ir) : env_info =
  let runtime =
    Why_runtime_view.of_ir_node
      ~simplify_runtime_actions:simplify_why3_runtime_actions
      ~slice_transition_bodies:slice_why3_transition_bodies node
  in
  prepare_runtime_view ~temporal_layout:node.temporal_layout runtime

let product_step_helper_name = Step_names.product_step_helper_name
let product_step_group_helper_name = Step_names.product_step_group_helper_name

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
  let type_state = info.type_state in
  let type_enum_decls = info.type_enum_decls in
  let type_vars = info.type_vars in
  let env = info.env in
  let function_decls =
    List.map compile_pure_function_decl runtime_view.function_decls
  in
  let inputs = info.inputs in
  (* Locals and outputs as vdecl list (needed for getter generation). *)
  let locals_and_outputs =
    List.map port_view_to_vdecl (runtime_view.locals @ runtime_view.outputs)
  in
  let getter_decls =
    let mk_getter (v : vdecl) =
      let field_name = v.vname in
      let getter_name = ident ("get_" ^ field_name) in
      let arg =
        (loc, Some (ident "self"), false, Some (Ptree.PTtyapp (qid1 "vars", [])))
      in
      let body =
        compile_expr
          { env with rec_name = "self" }
          { expr = EVar field_name; loc = None }
      in
      let fn =
        mk_expr
          (Efun
             ( [ arg ],
               Some (default_pty v.vty),
               { pat_desc = Pwild; pat_loc = loc },
               Ity.MaskVisible,
               empty_spec (),
               body ))
      in
      Ptree.Dlet (getter_name, false, Expr.RKnone, fn)
    in
    List.map mk_getter locals_and_outputs
  in
  let logic_getter_decls =
    let mk (v : vdecl) = logic_getter_decl ~env v.vname v.vty in
    logic_getter_decl ~env "st" (TCustom "state")
    :: List.map mk locals_and_outputs
  in
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
  let import_module = Modules.import_module in
  let common_module_name = Modules.common_module_name module_name in
  let common_import = import_module common_module_name in
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

  let common_decls =
    imports @ type_enum_decls @ function_decls @ [ type_state; type_vars ]
    @ getter_decls @ logic_getter_decls
  in
  Modules.assemble_node_modules ~module_name ~imports ~common_module_name
    ~common_import ~common_decls
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
    (prepare_ir_node ~simplify_why3_runtime_actions
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
