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
open Why_compile_expr
open Why_compile_ptree_helpers

module StringSet = Why_compile_ptree_helpers.StringSet

type 'groups module_unit =
  Ptree.ident * Ptree.qualid option * Ptree.decl list * 'groups

type 'groups context = {
  module_name : string;
  imports : Ptree.decl list;
  common_import : Ptree.decl;
  inputs : Ptree.binder list;
  empty_groups : unit -> 'groups;
  local_shared_formula_decls : ?exclude:StringSet.t -> StringSet.t -> Ptree.decl list;
  shared_formula_names_in_terms : Ptree.term list -> StringSet.t;
}

let predicate_bundle_decl_and_call ~(inputs : Ptree.binder list) ~(name : string)
    (terms : Ptree.term list) =
  let body = term_and_list terms in
  let used = names_of_term body StringSet.empty in
  let used_inputs =
    inputs
    |> List.filter (fun (_, id_opt, _, _) ->
           match id_opt with
           | Some id -> StringSet.mem id.id_str used
           | None -> false)
  in
  let params = List.filter_map param_of_binder used_inputs in
  let args = List.filter_map binder_term used_inputs in
  let decl =
    Ptree.Dlogic
      [
        {
          ld_loc = loc;
          ld_ident = ident name;
          ld_params = params;
          ld_type = None;
          ld_def = Some body;
        };
      ]
  in
  (decl, mk_term (Tidapp (qid1 name, args)))

let import_module name = Ptree.Duseimport (loc, false, [ (qid1 name, None) ])

let shared_bundle_call ~(context : 'groups context) ~(module_suffix : string)
    ~(predicate_prefix : string) ~(table : (string, string * string) Hashtbl.t)
    ~(modules : 'groups module_unit list ref) (terms : Ptree.term list) =
  let body = term_and_list terms in
  let key = string_of_term body in
  let shared_names = context.shared_formula_names_in_terms [ body ] in
  let used_names = names_of_term body StringSet.empty in
  let bundle_imports =
    Hashtbl.to_seq_values table
    |> Seq.filter_map (fun (bundle_module_name, name) ->
           if StringSet.mem name used_names then Some (import_module bundle_module_name)
           else None)
    |> List.of_seq
  in
  let used_inputs =
    context.inputs
    |> List.filter (fun (_, id_opt, _, _) ->
           match id_opt with
           | Some id -> StringSet.mem id.id_str used_names
           | None -> false)
  in
  let params = List.filter_map param_of_binder used_inputs in
  let args = List.filter_map binder_term used_inputs in
  let bundle_module_name, name =
    match Hashtbl.find_opt table key with
    | Some existing -> existing
    | None ->
        let index = Hashtbl.length table + 1 in
        let bundle_module_name =
          Printf.sprintf "%s__%s_%03d" context.module_name module_suffix index
        in
        let name = Printf.sprintf "%s_%03d" predicate_prefix index in
        let decl =
          Ptree.Dlogic
            [
              {
                ld_loc = loc;
                ld_ident = ident name;
                ld_params = params;
                ld_type = None;
                ld_def = Some body;
              };
            ]
        in
        Hashtbl.add table key (bundle_module_name, name);
        let shared_decls = context.local_shared_formula_decls shared_names in
        modules :=
          ( ident bundle_module_name,
            None,
            context.imports
            @ [ context.common_import ]
            @ bundle_imports @ shared_decls @ [ decl ],
            context.empty_groups () )
          :: !modules;
        (bundle_module_name, name)
  in
  (import_module bundle_module_name, mk_term (Tidapp (qid1 name, args)), shared_names)

let bundle_key terms = string_of_term (term_and_list terms)

let remove_terms removed terms =
  let removed_keys =
    removed
    |> List.map string_of_term
    |> List.fold_left (fun acc key -> StringSet.add key acc) StringSet.empty
  in
  List.filter (fun term -> not (StringSet.mem (string_of_term term) removed_keys)) terms

let count_bundles bundles =
  let counts = Hashtbl.create 64 in
  List.iter
    (fun terms ->
      if List.length terms > 1 then
        let key = bundle_key terms in
        let count = Option.value ~default:0 (Hashtbl.find_opt counts key) in
        Hashtbl.replace counts key (count + 1))
    bundles;
  counts

let should_share_bundle counts terms =
  List.length terms > 1
  &&
  match Hashtbl.find_opt counts (bundle_key terms) with
  | Some count -> count > 1
  | None -> false
