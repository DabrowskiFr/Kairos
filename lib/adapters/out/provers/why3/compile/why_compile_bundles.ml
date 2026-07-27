(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frederic Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

(** Compact predicates for multi-clause helper contracts. *)

open Why3
open Ptree
open Why_compile_expr
open Why_compile_ptree_helpers

type t = {
  module_name : string;
  imports : Ptree.decl list;
  common_import : Ptree.decl;
  inputs : Ptree.binder list;
  formula_imports : Core_syntax.history_free Ir.summary_formula list -> Ptree.decl list;
  post_table : (Ptree.term, string * Ptree.term) Hashtbl.t;
  mutable post_modules_rev : (Ptree.ident * Ptree.decl list) list;
}

let create ~module_name ~imports ~common_import ~inputs ~formula_imports =
  {
    module_name;
    imports;
    common_import;
    inputs;
    formula_imports;
    post_table = Hashtbl.create 32;
    post_modules_rev = [];
  }

let predicate_decl_and_call ~inputs ~used_inputs ~name terms =
  let body = term_and_list terms in
  let used_inputs =
    List.filter
      (fun (_, id_opt, _, _) ->
        match id_opt with
        | Some id -> StringSet.mem id.id_str used_inputs
        | None -> false)
      inputs
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

let shared_post_call state ~used_inputs ~formulas terms =
  let key = term_and_list terms in
  match Hashtbl.find_opt state.post_table key with
  | Some (module_name, call) -> (import_module module_name, call)
  | None ->
      let index = Hashtbl.length state.post_table + 1 in
      let module_name =
        Printf.sprintf "%s__Post_%03d" state.module_name index
      in
      let predicate_name =
        Printf.sprintf "shared_post_bundle_%03d" index
      in
      let decl, call =
        predicate_decl_and_call ~inputs:state.inputs ~used_inputs
          ~name:predicate_name terms
      in
      Hashtbl.add state.post_table key (module_name, call);
      state.post_modules_rev <-
        ( ident module_name,
          state.imports @ [ state.common_import ]
          @ state.formula_imports formulas
          @ [ decl ] )
        :: state.post_modules_rev;
      (import_module module_name, call)

let shared_post_modules state = List.rev state.post_modules_rev
