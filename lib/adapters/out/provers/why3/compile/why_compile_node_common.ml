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
open Ptree
open Core_syntax
open Why_compile_expr
open Why_compile_logic

module Node_getters = Why_compile_node_getters
module Node_inputs = Why_compile_node_inputs
module Node_types = Why_compile_node_types

type t = {
  runtime_view : Why_runtime_view.t;
  module_name : string;
  imports : Ptree.decl list;
  common_module_name : string;
  common_import : Ptree.decl;
  env : Why_compile_expr.env;
  inputs : Ptree.binder list;
  common_decls : Ptree.decl list;
}

let module_name_of_node (name : Core_syntax.ident) : string =
  String.capitalize_ascii name

let imports =
  [
    Duseimport (loc, false, [ (qid1 "int.Int", None) ]);
    Duseimport (loc, false, [ (qid1 "array.Array", None) ]);
  ]

let prepare_runtime_view ~(temporal_layout : Ir.temporal_layout)
    (runtime : Why_runtime_view.t) : t =
  let module_name = module_name_of_node runtime.node_name in
  let common_module_name = Why_compile_modules.common_module_name module_name in
  let common_import = Why_compile_modules.import_module common_module_name in
  let type_state = Node_types.compile_state_type runtime in
  let type_enum_decls = Node_types.compile_enum_types runtime in
  let type_vars = Node_types.compile_vars_type runtime in
  let rec_vars =
    "st"
    :: List.map
         (fun (p : Why_runtime_view.port_view) -> p.port_name)
         (runtime.locals @ runtime.outputs)
  in
  let env = { rec_name = "vars"; rec_vars; links = [] } in
  let inputs = Node_inputs.compile_inputs temporal_layout runtime in
  let function_decls =
    List.map compile_pure_function_decl runtime.function_decls
  in
  let locals_and_outputs =
    List.map port_view_to_vdecl (runtime.locals @ runtime.outputs)
  in
  let getter_decls = Node_getters.compile_getter_decls env locals_and_outputs in
  let logic_getter_decls =
    Node_getters.compile_logic_getter_decls env locals_and_outputs
  in
  let common_decls =
    imports @ type_enum_decls @ function_decls @ [ type_state; type_vars ]
    @ getter_decls @ logic_getter_decls
  in
  {
    runtime_view = runtime;
    module_name;
    imports;
    common_module_name;
    common_import;
    env;
    inputs;
    common_decls;
  }

let prepare_ir_node ?(simplify_why3_runtime_actions = true)
    ?(slice_why3_transition_bodies = true) (node : Ir.node_ir) : t =
  let runtime =
    Why_runtime_view.of_ir_node
      ~simplify_runtime_actions:simplify_why3_runtime_actions
      ~slice_transition_bodies:slice_why3_transition_bodies node
  in
  prepare_runtime_view ~temporal_layout:node.temporal_layout runtime
