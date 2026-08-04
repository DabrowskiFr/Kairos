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
open Kr_domain_core_syntax
open Why_compile_expr

let why_type_name name =
  if String.equal name "state" then "state"
  else "kr_" ^ String.uncapitalize_ascii name

let compile_state_type (semantics : Kr_verification_ir.node_signature) =
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

let compile_enum_types (semantics : Kr_verification_ir.node_signature) =
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

let compile_vars_type (semantics : Kr_verification_ir.node_signature) =
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

open Kr_domain_core.Kr_domain_core_history

let compile_inputs temporal_layout (semantics : Kr_verification_ir.node_signature) =
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
    |> List.concat_map (fun (info : Kr_domain_core.Kr_domain_core_history.pre_k_info) ->
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

let module_name_of_node (name : Kr_domain_core_syntax.ident) : string =
  String.capitalize_ascii name

let imports =
  [
    Duseimport (loc, false, [ (qid1 "int.Int", None) ]);
    Duseimport (loc, false, [ (qid1 "array.Array", None) ]);
    Duseimport (loc, false, [ (qid1 "ref.Ref", None) ]);
  ]

let method_calls (decl : method_decl) =
  let rec calls_of_stmt acc (stmt : stmt) =
    match stmt.stmt with
    | SMethodCall (name, _) ->
        if List.mem name acc then acc else name :: acc
    | SIf (_, left, right) -> List.fold_left calls_of_stmt acc (left @ right)
    | SWhile (_, _, _, body) -> List.fold_left calls_of_stmt acc body
    | SMatch (_, branches, default_branch) ->
        List.fold_left calls_of_stmt acc
          (List.concat_map snd branches @ default_branch)
    | SAssign _ | SAssert _ | SSkip -> acc
  in
  List.fold_left calls_of_stmt [] decl.method_body

let order_methods methods =
  let by_name =
    List.map (fun (decl : method_decl) -> (decl.method_name, decl)) methods
  in
  let visited = Hashtbl.create 17 in
  let rec visit acc name =
    if Hashtbl.mem visited name then acc
    else (
      Hashtbl.replace visited name ();
      let decl = List.assoc name by_name in
      let acc = List.fold_left visit acc (method_calls decl) in
      decl :: acc)
  in
  List.fold_left
    (fun acc (decl : method_decl) -> visit acc decl.method_name)
    [] methods
  |> List.rev

let compile_method_decl base_env (decl : method_decl) =
  let inout_names =
    List.filter_map
      (fun (param : method_param) ->
        match param.method_param_mode with
        | MPIn -> None
        | MPInOut -> Some param.method_param_name)
      decl.method_params
  in
  let env = { base_env with ref_vars = inout_names } in
  let vars_binder =
    (loc, Some (ident env.rec_name), false, Some (PTtyapp (qid1 "vars", [])))
  in
  let input_binders =
    List.map
      (fun (input : vdecl) ->
        (loc, Some (ident input.vname), false, Some (default_pty input.vty)))
      env.input_vars
  in
  let explicit_binders =
    List.map
      (fun (param : method_param) ->
        let pty =
          match param.method_param_mode with
          | MPIn -> default_pty param.method_param_ty
          | MPInOut ->
              PTtyapp (qid1 "ref", [ default_pty param.method_param_ty ])
        in
        (loc, Some (ident param.method_param_name), false, Some pty))
      decl.method_params
  in
  let post term =
    (loc, [ ({ pat_desc = Pwild; pat_loc = loc }, term) ])
  in
  let field_term name =
    mk_term
      (Tidapp
         (qid1 name, [ mk_term (Tident (qid1 env.rec_name)) ]))
  in
  let writes =
    List.map field_term decl.method_writes
    @ List.map (fun name -> mk_term (Tident (qid1 name))) inout_names
  in
  let spec =
    {
      Ptree.sp_pre = List.map (compile_hexpr env) decl.method_requires;
      sp_post = List.map (fun formula -> post (compile_method_post env formula)) decl.method_ensures;
      sp_xpost = [];
      sp_reads = [];
      sp_writes = writes;
      sp_alias = [];
      sp_variant = [];
      sp_checkrw = false;
      sp_diverge = false;
      sp_partial = false;
    }
  in
  let fn =
    mk_expr
      (Efun
         ( vars_binder :: input_binders @ explicit_binders,
           None,
           { pat_desc = Pwild; pat_loc = loc },
           Ity.MaskVisible,
           spec,
           Why_compile_step.compile_seq env decl.method_body ))
  in
  Dlet (ident decl.method_name, false, Expr.RKnone, fn)

let prepare ~(semantics : Kr_verification_ir.node_signature)
    ~(temporal_layout : Kr_verification_ir.temporal_layout) : t =
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
  let env =
    {
      rec_name = "vars";
      rec_vars;
      ref_vars = [];
      input_vars = semantics.sem_inputs;
      methods = semantics.sem_methods;
      used_inputs = None;
    }
  in
  let inputs = compile_inputs temporal_layout semantics in
  let function_decls =
    List.map compile_pure_function_decl semantics.sem_function_decls
  in
  let method_decls =
    order_methods semantics.sem_methods
    |> List.map (compile_method_decl env)
  in
  let common_decls =
    imports @ type_enum_decls @ function_decls @ [ type_state; type_vars ]
    @ method_decls
  in
  {
    module_name;
    imports;
    env;
    inputs;
    common_decls;
  }
