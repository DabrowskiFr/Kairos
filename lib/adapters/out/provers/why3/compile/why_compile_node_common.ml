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
open Pre_k_layout
open Why_compile_expr
open Why_compile_logic
open Why_compile_ptree_helpers

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

let why_type_name name =
  if String.equal name "state" then "state"
  else "kairos_" ^ String.uncapitalize_ascii name

let module_name_of_node (name : Core_syntax.ident) : string =
  String.capitalize_ascii name

let imports =
  [
    Duseimport (loc, false, [ (qid1 "int.Int", None) ]);
    Duseimport (loc, false, [ (qid1 "array.Array", None) ]);
  ]

let compile_state_type (runtime : Why_runtime_view.t) =
  Dtype
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

let compile_enum_types (runtime : Why_runtime_view.t) =
  runtime.type_decls
  |> List.map (fun (decl : enum_decl) ->
         Dtype
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

let mutable_field (v : Why_runtime_view.port_view) =
  {
    f_loc = loc;
    f_ident = ident v.port_name;
    f_pty = default_pty v.port_type;
    f_mutable = true;
    f_ghost = false;
  }

let compile_vars_type (runtime : Why_runtime_view.t) =
  let fields : Ptree.field list =
    {
      f_loc = loc;
      f_ident = ident "st";
      f_pty = PTtyapp (qid1 "state", []);
      f_mutable = true;
      f_ghost = false;
    }
    :: List.map mutable_field (runtime.locals @ runtime.outputs)
  in
  Dtype
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

let compile_inputs temporal_layout (runtime : Why_runtime_view.t) =
  let vars_param =
    (loc, Some (ident "vars"), false, Some (PTtyapp (qid1 "vars", [])))
  in
  let input_binders =
    List.map
      (fun (v : Why_runtime_view.port_view) ->
        (loc, Some (ident v.port_name), false, Some (default_pty v.port_type)))
      runtime.inputs
  in
  let pre_k_binders =
    let seen = Hashtbl.create 16 in
    temporal_layout
    |> List.concat_map (fun (info : Pre_k_layout.pre_k_info) ->
           info.names
           |> List.filter_map (fun name ->
                  if Hashtbl.mem seen name then None
                  else (
                    Hashtbl.add seen name ();
                    Some
                      ( loc,
                        Some (ident name),
                        false,
                        Some (default_pty info.vty) ))))
  in
  vars_param :: (input_binders @ pre_k_binders)

let compile_getter_decls env locals_and_outputs =
  let mk_getter (v : vdecl) =
    let field_name = v.vname in
    let getter_name = ident ("get_" ^ field_name) in
    let arg =
      (loc, Some (ident "self"), false, Some (PTtyapp (qid1 "vars", [])))
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
    Dlet (getter_name, false, Expr.RKnone, fn)
  in
  List.map mk_getter locals_and_outputs

let compile_logic_getter_decls env locals_and_outputs =
  let mk (v : vdecl) = logic_getter_decl ~env v.vname v.vty in
  logic_getter_decl ~env "st" (TCustom "state")
  :: List.map mk locals_and_outputs

let prepare_runtime_view ~(temporal_layout : Ir.temporal_layout)
    (runtime : Why_runtime_view.t) : t =
  let module_name = module_name_of_node runtime.node_name in
  let common_module_name = Why_compile_modules.common_module_name module_name in
  let common_import = Why_compile_modules.import_module common_module_name in
  let type_state = compile_state_type runtime in
  let type_enum_decls = compile_enum_types runtime in
  let type_vars = compile_vars_type runtime in
  let rec_vars =
    "st"
    :: List.map
         (fun (p : Why_runtime_view.port_view) -> p.port_name)
         (runtime.locals @ runtime.outputs)
  in
  let env = { rec_name = "vars"; rec_vars; links = [] } in
  let inputs = compile_inputs temporal_layout runtime in
  let function_decls =
    List.map compile_pure_function_decl runtime.function_decls
  in
  let locals_and_outputs =
    List.map port_view_to_vdecl (runtime.locals @ runtime.outputs)
  in
  let getter_decls = compile_getter_decls env locals_and_outputs in
  let logic_getter_decls =
    compile_logic_getter_decls env locals_and_outputs
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
