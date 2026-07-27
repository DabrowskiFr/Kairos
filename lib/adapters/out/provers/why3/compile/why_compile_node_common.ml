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


(** Common WhyML declarations and compilation context for one Kairos node. *)

open Why3
open Ptree
open Core_syntax
open Why_compile_expr

let why_type_name name =
  if String.equal name "state" then "state"
  else "kairos_" ^ String.uncapitalize_ascii name

let compile_state_type (semantics : Ir.node_signature) =
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
            (List.map (fun s -> (loc, ident s, [])) semantics.sem_states);
      };
    ]

let compile_enum_types (semantics : Ir.node_signature) =
  semantics.sem_type_decls
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

let mutable_field (v : vdecl) =
  {
    f_loc = loc;
    f_ident = ident v.vname;
    f_pty = default_pty v.vty;
    f_mutable = true;
    f_ghost = false;
  }

let compile_vars_type (semantics : Ir.node_signature) =
  let fields : Ptree.field list =
    {
      f_loc = loc;
      f_ident = ident "st";
      f_pty = PTtyapp (qid1 "state", []);
      f_mutable = true;
      f_ghost = false;
    }
    :: List.map mutable_field
         (semantics.sem_locals @ semantics.sem_outputs)
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

open Pre_k_layout

let compile_inputs temporal_layout (semantics : Ir.node_signature) =
  let vars_param =
    (loc, Some (ident "vars"), false, Some (PTtyapp (qid1 "vars", [])))
  in
  let input_binders =
    List.map
      (fun (v : vdecl) ->
        (loc, Some (ident v.vname), false, Some (default_pty v.vty)))
      semantics.sem_inputs
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

open Why_compile_logic

type t = {
  module_name : string;
  imports : Ptree.decl list;
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

let prepare_ir_node (node : Core_syntax.history_free Ir.node_ir) : t =
  let semantics = node.semantics in
  let module_name = module_name_of_node semantics.sem_nname in
  let type_state = compile_state_type semantics in
  let type_enum_decls = compile_enum_types semantics in
  let type_vars = compile_vars_type semantics in
  let rec_vars =
    "st"
    :: List.map
         (fun (v : vdecl) -> v.vname)
         (semantics.sem_locals @ semantics.sem_outputs)
  in
  let env = { rec_name = "vars"; rec_vars; used_inputs = None } in
  let inputs = compile_inputs node.temporal_layout semantics in
  let function_decls =
    List.map compile_pure_function_decl semantics.sem_function_decls
  in
  let common_decls =
    imports @ type_enum_decls @ function_decls @ [ type_state; type_vars ]
  in
  {
    module_name;
    imports;
    env;
    inputs;
    common_decls;
  }
