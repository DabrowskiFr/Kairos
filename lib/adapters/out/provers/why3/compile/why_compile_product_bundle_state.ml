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

module Bundles = Why_compile_bundles
module Modules = Why_compile_modules
module StringSet = Why_compile_ptree_helpers.StringSet

type context = {
  module_name : string;
  imports : Why3.Ptree.decl list;
  common_import : Why3.Ptree.decl;
  inputs : Why3.Ptree.binder list;
  local_shared_formula_decls :
    ?exclude:StringSet.t -> StringSet.t -> Why3.Ptree.decl list;
  shared_formula_names_in_terms : Why3.Ptree.term list -> StringSet.t;
}

type t = {
  predicate_bundle_decl_and_call_fn :
    name:string -> Why3.Ptree.term list -> Why3.Ptree.decl * Why3.Ptree.term;
  shared_pre_bundle_call_fn :
    Why3.Ptree.term list -> Why3.Ptree.decl * Why3.Ptree.term * StringSet.t;
  shared_post_bundle_call_fn :
    Why3.Ptree.term list -> Why3.Ptree.decl * Why3.Ptree.term * StringSet.t;
  shared_pre_bundle_modules_ref : Modules.module_unit list ref;
  shared_post_bundle_modules_ref : Modules.module_unit list ref;
}

let create ctx =
  let bundle_context : Modules.spec_groups Bundles.context =
    {
      module_name = ctx.module_name;
      imports = ctx.imports;
      common_import = ctx.common_import;
      inputs = ctx.inputs;
      empty_groups = Modules.empty_groups;
      local_shared_formula_decls = ctx.local_shared_formula_decls;
      shared_formula_names_in_terms = ctx.shared_formula_names_in_terms;
    }
  in
  let shared_bundle_call = Bundles.shared_bundle_call ~context:bundle_context in
  let shared_pre_bundle_table : (string, string * string) Hashtbl.t =
    Hashtbl.create 128
  in
  let shared_pre_bundle_modules_ref = ref [] in
  let shared_pre_bundle_call_fn =
    shared_bundle_call ~module_suffix:"Pre"
      ~predicate_prefix:"shared_pre_bundle"
      ~table:shared_pre_bundle_table ~modules:shared_pre_bundle_modules_ref
  in
  let shared_post_bundle_table : (string, string * string) Hashtbl.t =
    Hashtbl.create 128
  in
  let shared_post_bundle_modules_ref = ref [] in
  let shared_post_bundle_call_fn =
    shared_bundle_call ~module_suffix:"Post"
      ~predicate_prefix:"shared_post_bundle"
      ~table:shared_post_bundle_table ~modules:shared_post_bundle_modules_ref
  in
  {
    predicate_bundle_decl_and_call_fn =
      Bundles.predicate_bundle_decl_and_call ~inputs:ctx.inputs;
    shared_pre_bundle_call_fn;
    shared_post_bundle_call_fn;
    shared_pre_bundle_modules_ref;
    shared_post_bundle_modules_ref;
  }

let predicate_bundle_decl_and_call state =
  state.predicate_bundle_decl_and_call_fn

let shared_pre_bundle_call state = state.shared_pre_bundle_call_fn
let shared_post_bundle_call state = state.shared_post_bundle_call_fn
let shared_pre_bundle_modules state = List.rev !(state.shared_pre_bundle_modules_ref)

let shared_post_bundle_modules state =
  List.rev !(state.shared_post_bundle_modules_ref)
