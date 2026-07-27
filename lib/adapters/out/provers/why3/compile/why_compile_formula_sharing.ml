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
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *---------------------------------------------------------------------------*)

(** WhyML emission for formulas selected by the domain-level index. *)

open Why3
open Ptree
open Why_compile_expr
open Why_compile_ptree_helpers

type shared_formula = {
  name : string;
  uses_record : bool;
  input_binders : Ptree.binder list;
}

type t = {
  formula_index : Contract_formula_index.t;
  entries : (Contract_formula_index.formula_id, shared_formula) Hashtbl.t;
  definitions : (shared_formula * Ptree.decl) list;
}

let module_name node_module formula_name =
  node_module ^ "__" ^ formula_name

let definition_modules sharing ~module_name:node_module ~imports ~common_import =
  List.map
    (fun (shared, declaration) ->
      ( ident (module_name node_module shared.name),
        imports @ [ common_import; declaration ] ))
    sharing.definitions

let imports_for sharing ~module_name:node_module formulas =
  let used_names =
    List.fold_left
      (fun names (formula : Core_syntax.history_free Ir.summary_formula) ->
        match Contract_formula_index.find sharing.formula_index formula with
        | None -> names
        | Some definition ->
            let shared = Hashtbl.find sharing.entries definition.id in
            StringSet.add shared.name names)
      StringSet.empty formulas
  in
  sharing.definitions
  |> List.filter_map (fun (shared, _declaration) ->
         if StringSet.mem shared.name used_names then
           Some (import_module (module_name node_module shared.name))
         else None)

let binder_name (_, id_opt, _, _) =
  Option.map (fun id -> id.Ptree.id_str) id_opt

let input_binders_used_by used inputs =
  match inputs with
  | [] -> []
  | _vars :: direct_inputs ->
      List.filter
        (fun binder ->
          match binder_name binder with
          | None -> true
          | Some name -> StringSet.mem name used)
        direct_inputs

let record_param name =
  (loc, Some (ident name), false, Ptree.PTtyapp (qid1 "vars", []))

let make_shared_formula ~env ~inputs ~id
    (formula : Core_syntax.history_free Ir.summary_formula) =
  let record_name = "__shared_vars" in
  let body, used =
    collect_used_inputs env (fun env ->
        compile_hexpr { env with rec_name = record_name } formula.logic)
  in
  let uses_record = StringSet.mem record_name used in
  let input_binders = input_binders_used_by used inputs in
  let name = Printf.sprintf "__kairos_shared_formula_%d" id in
  let params =
    (if uses_record then [ record_param record_name ] else [])
    @ List.filter_map param_of_binder input_binders
  in
  let declaration =
    Dlogic
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
  ({ name; uses_record; input_binders }, declaration)

let build ~env ~inputs formula_index =
  let entries = Hashtbl.create 32 in
  let definitions = ref [] in
  Contract_formula_index.definitions formula_index
  |> List.iter (fun (definition : Contract_formula_index.definition) ->
         let shared, declaration =
           make_shared_formula ~env ~inputs ~id:definition.id
             definition.formula
         in
         Hashtbl.add entries definition.id shared;
         definitions := (shared, declaration) :: !definitions);
  { formula_index; entries; definitions = List.rev !definitions }

let compile sharing ~env formula =
  match Contract_formula_index.find sharing.formula_index formula with
  | None -> compile_hexpr env formula.logic
  | Some definition ->
      let shared = Hashtbl.find sharing.entries definition.id in
      let record_args =
        if shared.uses_record then begin
          note_input env env.rec_name;
          [ mk_term (Tident (qid1 env.rec_name)) ]
        end
        else []
      in
      let input_args =
        List.filter_map
          (fun binder ->
            Option.iter (note_input env) (binder_name binder);
            binder_term binder)
          shared.input_binders
      in
      mk_term (Tidapp (qid1 shared.name, record_args @ input_args))
