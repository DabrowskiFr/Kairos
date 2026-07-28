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

module Obligations =
  Kairos_verification_obligations.Verification_obligations

module Proof_ir =
  Kairos_verification_obligations.Verification_proof_ir

type t = {
  entries :
    (int, string * Ptree.term * Why_compile_expr.used_inputs) Hashtbl.t;
  modules : (Ptree.ident * Ptree.decl list) list;
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

let create ~module_name ~imports ~common_import ~env ~inputs
    ~formula_imports ~compile_conditions
    (shared_postconditions : Proof_ir.shared_postcondition list) =
  let entries = Hashtbl.create (List.length shared_postconditions) in
  let modules =
    List.map
      (fun (shared : Proof_ir.shared_postcondition) ->
        if Hashtbl.mem entries shared.id then
          invalid_arg
            (Printf.sprintf
               "Why_compile_bundles.create: duplicate shared \
                postcondition id %d"
               shared.id);
        let terms, used_inputs =
          collect_used_inputs env (fun env ->
              compile_conditions env shared.conditions)
        in
        let shared_module_name =
          Printf.sprintf "%s__Post_%03d" module_name shared.id
        in
        let predicate_name =
          Printf.sprintf "shared_post_bundle_%03d" shared.id
        in
        let declaration, call =
          predicate_decl_and_call ~inputs ~used_inputs
            ~name:predicate_name terms
        in
        Hashtbl.add entries shared.id
          (shared_module_name, call, used_inputs);
        ( ident shared_module_name,
          imports @ [ common_import ]
          @ formula_imports
              (Obligations.formulas_of_conditions shared.conditions)
          @ [ declaration ] ))
      shared_postconditions
  in
  { entries; modules }

let shared_postcondition_call state id =
  match Hashtbl.find_opt state.entries id with
  | Some (module_name, call, used_inputs) ->
      (import_module module_name, call, used_inputs)
  | None ->
      invalid_arg
        (Printf.sprintf
           "Why_compile_bundles.shared_postcondition_call: unknown id %d"
           id)

let shared_post_modules state = state.modules
