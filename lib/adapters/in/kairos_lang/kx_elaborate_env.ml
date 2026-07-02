(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
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
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *---------------------------------------------------------------------------*)

open Kx_core_syntax
module S = Kx_surface_syntax
module Names = Kx_elaborate_names

type env = {
  enum_sets : (ident * ident list) list;
  functions : (ident * (vdecl list * ty)) list;
  spec_defs : (ident * S.spec_def_decl) list;
  history_defs : (ident * S.history_def_decl) list;
  predicates : (ident * S.predicate_decl) list;
  actions : (ident * S.action_decl) list;
  history_aliases : (ident * (ident * int)) list;
}

let empty_env =
  {
    enum_sets = [];
    functions = [];
    spec_defs = [];
    history_defs = [];
    predicates = [];
    actions = [];
    history_aliases = [];
  }

type spec_context = {
  formula_params : (ident * S.ltl) list;
  hexpr_params : (ident * S.hexpr) list;
  nat_params : (ident * int) list;
  spec_stack : ident list;
}

let empty_spec_context =
  { formula_params = []; hexpr_params = []; nat_params = []; spec_stack = [] }

let add_unique_assoc what key value assoc =
  if List.mem_assoc key assoc then
    Kx_frontend_error.elaboration
      (Printf.sprintf "duplicate %s '%s'" what key)
  else (key, value) :: assoc

let add_enum_set env name members =
  if members = [] then
    Kx_frontend_error.well_formedness
      (Printf.sprintf "enum type '%s' has no constructors" name);
  { env with enum_sets = add_unique_assoc "enum type" name members env.enum_sets }

let enum_members env name =
  match List.assoc_opt name env.enum_sets with
  | Some members -> members
  | None ->
      Kx_frontend_error.elaboration
        (Printf.sprintf "unknown enum type '%s'" name)

let expand_enum_or_single env name =
  match List.assoc_opt name env.enum_sets with Some members -> members | None -> [ name ]

let cartesian_concat left right =
  List.concat_map (fun xs -> List.map (fun ys -> xs @ ys) right) left

let expand_index_product env atoms =
  List.fold_right
    (fun atom acc ->
      let choices = List.map (fun name -> [ name ]) (expand_enum_or_single env atom) in
      cartesian_concat choices acc)
    atoms [ [] ]

let expand_index_choices env choices =
  List.concat_map (expand_index_product env) choices

let lower_raw_vdecl env (raw : S.raw_vdecl) : vdecl list =
  match raw.raw_indices with
  | None -> [ { vname = raw.raw_vname; vty = raw.raw_vty } ]
  | Some choices ->
      expand_index_choices env choices
      |> List.map (fun idxs ->
             { vname = Names.indexed_ident_many raw.raw_vname idxs; vty = raw.raw_vty })

let lower_raw_vdecls env raws = List.concat_map (lower_raw_vdecl env) raws

let rec range_values lo hi =
  if lo > hi then [] else lo :: range_values (lo + 1) hi

let eval_nat ctx = function
  | S.SNNat n ->
      if n < 0 then
        Kx_frontend_error.well_formedness
          "natural number literal must be non-negative";
      n
  | S.SNVar id -> (
      match List.assoc_opt id ctx.nat_params with
      | Some n -> n
      | None ->
          Kx_frontend_error.elaboration
            (Printf.sprintf "unknown Nat parameter '%s'" id))

let function_sig env name = List.assoc_opt name env.functions

let is_bool_function env name =
  match function_sig env name with Some (_, TBool) -> true | Some _ | None -> false
