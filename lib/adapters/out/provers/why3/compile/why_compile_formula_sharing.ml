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

open Core_syntax

module Deps = Why_compile_formula_sharing_deps
module Emit = Why_compile_formula_sharing_emit
module Inventory = Why_compile_formula_sharing_inventory
module StringSet = Why_compile_ptree_helpers.StringSet

type context = {
  env : Why_compile_expr.env;
  inputs : Why3.Ptree.binder list;
  runtime_view : Why_runtime_view.t;
  share_why3_facts : bool;
}

type t = {
  shared_formula_decls : (string * Why3.Ptree.decl) list;
  abstract_formula : in_post:bool -> Core_syntax.hexpr -> Why3.Ptree.term option;
  abstract_formula_with_rec :
    string -> Core_syntax.hexpr -> Why3.Ptree.term option;
  local_cut_candidate : Core_syntax.hexpr -> bool;
  shared_formula_names_in_terms : Why3.Ptree.term list -> StringSet.t;
  local_shared_formula_decls :
    ?exclude:StringSet.t -> StringSet.t -> Why3.Ptree.decl list;
  local_shared_formula_imports :
    module_name_of_formula:(string -> string) ->
    ?exclude:StringSet.t ->
    StringSet.t ->
    Why3.Ptree.decl list;
  shared_formula_closure : ?exclude:StringSet.t -> StringSet.t -> StringSet.t;
}

let empty_selection () : Inventory.selection =
  { table = Hashtbl.create 0; order = [] }

let local_cut_candidate (formula : Core_syntax.hexpr) =
  let emit_local_unfolded_cuts = false in
  emit_local_unfolded_cuts
  &&
  match formula.hexpr with
  | HBin ((And | Or), _, _) | HUn (Not, _) | HPred _ -> true
  | HLitInt _ | HLitBool _ | HLitEnum _ | HVar _ | HPreK _ | HFunCall _
  | HUn (Neg, _)
  | HBin ((Add | Sub | Mul | Div), _, _)
  | HCmp _ ->
      false

let build ctx =
  let selection =
    if ctx.share_why3_facts then
      Inventory.select ~env:ctx.env ~inputs:ctx.inputs
        ~runtime_view:ctx.runtime_view
    else empty_selection ()
  in
  let shared_formula_call name params use_self =
    Emit.shared_formula_call_with_rec ctx.env.rec_name name params use_self
  in
  let abstract_formula ~in_post:_ (formula : Core_syntax.hexpr) =
    if not ctx.share_why3_facts then None
    else
      Hashtbl.find_opt selection.table (Inventory.formula_key formula)
      |> Option.map (fun (name, params, _, use_self) ->
             shared_formula_call name params use_self)
  in
  let abstract_formula_with_rec rec_name (formula : Core_syntax.hexpr) =
    if not ctx.share_why3_facts then None
    else
      Hashtbl.find_opt selection.table (Inventory.formula_key formula)
      |> Option.map (fun (name, params, _, use_self) ->
             Emit.shared_formula_call_with_rec rec_name name params use_self)
  in
  let shared_formula_entries =
    if not ctx.share_why3_facts then []
    else
      Emit.build_shared_formula_entries ~env:ctx.env ~table:selection.table
        ~order:selection.order
  in
  let shared_formula_decls =
    List.map
      (fun (name, _formula, decl) -> (name, decl))
      shared_formula_entries
  in
  let shared_formula_index =
    Deps.build_index ~table:selection.table ~entries:shared_formula_entries
  in
  let local_shared_formula_decls ?exclude names =
    Deps.local_shared_formula_decls shared_formula_index ?exclude names
  in
  let local_shared_formula_imports ~module_name_of_formula ?exclude names =
    Deps.local_shared_formula_imports shared_formula_index ~module_name_of_formula
      ?exclude names
  in
  let formula_dependency_closure ?exclude names =
    Deps.shared_formula_closure shared_formula_index ?exclude names
  in
  {
    shared_formula_decls;
    abstract_formula;
    abstract_formula_with_rec;
    local_cut_candidate;
    shared_formula_names_in_terms = Deps.shared_formula_names_in_terms;
    local_shared_formula_decls;
    local_shared_formula_imports;
    shared_formula_closure = formula_dependency_closure;
  }
