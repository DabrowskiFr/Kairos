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
open Why3

module Inventory = Why_compile_formula_sharing_inventory
module Emit = Why_compile_formula_sharing_emit
open Why_compile_expr_primitives
open Why_compile_ptree_helpers
module StringSet = Why_compile_ptree_helpers.StringSet

type shared_entry = Inventory.shared_entry
type shared_formula_decl = Emit.shared_formula_decl

type index = {
  entries : shared_formula_decl list;
  deps_by_name : (string * StringSet.t) list;
}

let shared_formula_names_in_term term =
  Why_compile_ptree_helpers.names_of_term term StringSet.empty
  |> StringSet.filter (String.starts_with ~prefix:"shared_contract_formula_")

let shared_formula_names_in_terms terms =
  List.fold_left
    (fun acc term -> StringSet.union acc (shared_formula_names_in_term term))
    StringSet.empty terms

let direct_shared_formula_deps table (formula : Core_syntax.hexpr) =
  let rec go current_key h acc =
    let key = Inventory.formula_key h in
    match Hashtbl.find_opt table key with
    | Some (name, _, _, _) when not (String.equal key current_key) ->
        StringSet.add name acc
    | _ ->
        begin
          match h.hexpr with
          | HLitInt _ | HLitBool _ | HLitEnum _ | HVar _ | HPreK _ -> acc
          | HUn (_, inner) -> go current_key inner acc
          | HPred (_, hs) | HFunCall (_, hs) ->
              List.fold_left (fun acc h -> go current_key h acc) acc hs
          | HBin (_, a, b) | HCmp (_, a, b) ->
              go current_key b (go current_key a acc)
        end
  in
  go (Inventory.formula_key formula) formula StringSet.empty

let shared_formula_closure_names deps_by_name names =
  let rec loop seen work =
    match work with
    | [] -> seen
    | name :: rest ->
        if StringSet.mem name seen then loop seen rest
        else
          let deps =
            Option.value
              (List.assoc_opt name deps_by_name)
              ~default:StringSet.empty
            |> StringSet.elements
          in
          loop (StringSet.add name seen) (deps @ rest)
  in
  loop StringSet.empty (StringSet.elements names)

let build_index ~table ~entries =
  let deps_by_name =
    entries
    |> List.map (fun (name, formula, _decl) ->
           (name, direct_shared_formula_deps table formula))
  in
  { entries; deps_by_name }

let shared_formula_closure index ?(exclude = StringSet.empty) names =
  let closure = shared_formula_closure_names index.deps_by_name names in
  StringSet.union names (StringSet.diff closure exclude)

let local_shared_formula_decls index ?(exclude = StringSet.empty) names =
  let closure = shared_formula_closure index ~exclude names in
  index.entries
  |> List.filter_map (fun (name, _formula, decl) ->
         if StringSet.mem name closure then Some decl else None)

let local_shared_formula_imports index ~module_name_of_formula
    ?(exclude = StringSet.empty) names =
  let closure = shared_formula_closure index ~exclude names in
  closure
  |> StringSet.elements
  |> List.map (fun name ->
         Ptree.Duseimport
           (loc, false, [ (qid1 (module_name_of_formula name), None) ]))
