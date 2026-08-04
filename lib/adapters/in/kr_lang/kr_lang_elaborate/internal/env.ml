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

open Kr_lang_core.Kr_lang_core_syntax
(* Internal module used by the elaboration pipeline. *)
module S = Kr_lang_surface.Kr_lang_surface_ast

type env = {
  enum_sets : (ident * ident list) list;
  variables : (ident * ty) list;
  functions : (ident * (vdecl list * ty)) list;
  spec_defs : (ident * S.spec_def_decl) list;
  predicates : (ident * S.predicate_decl) list;
  methods : (ident * S.method_decl) list;
  history_aliases : (ident * (ident * int)) list;
}

let empty_env =
  {
    enum_sets = [];
    variables = [];
    functions = [];
    spec_defs = [];
    predicates = [];
    methods = [];
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

(* [add_unique_assoc what key value assoc] prepends a named entry to [assoc].
   It returns the extended association list and raises an elaboration error
   when [key] is already present. *)
let add_unique_assoc what key value assoc =
  if List.mem_assoc key assoc then
    Kr_lang_shared.Kr_lang_shared_error.elaboration (Printf.sprintf "duplicate %s '%s'" what key)
  else (key, value) :: assoc

(* [add_enum_decl env name members] registers a non-empty enum declaration.
   It returns the updated environment and rejects duplicate type or
   constructor names. *)
let add_enum_decl env name members =
  if members = [] then
    Kr_lang_shared.Kr_lang_shared_error.well_formedness
      (Printf.sprintf "enum type '%s' has no constructors" name);
  let constructors = Hashtbl.create (List.length members + 8) in
  List.iter
    (fun (enum_name, enum_members) ->
      List.iter (fun constructor -> Hashtbl.replace constructors constructor enum_name) enum_members)
    env.enum_sets;
  List.iter
    (fun constructor ->
      match Hashtbl.find_opt constructors constructor with
      | Some previous_type ->
          Kr_lang_shared.Kr_lang_shared_error.well_formedness
            (Printf.sprintf
               "enum constructor '%s' is declared in both '%s' and '%s'"
               constructor previous_type name)
      | None -> Hashtbl.add constructors constructor name)
    members;
  { env with enum_sets = add_unique_assoc "enum type" name members env.enum_sets }

(* [add_function env name signature] registers a pure-function signature.
   It returns the updated environment or raises on a duplicate name. *)
let add_function env name signature =
  { env with functions = add_unique_assoc "pure function" name signature env.functions }

(* [add_spec_def env name declaration] registers one specification definition.
   It returns the updated environment or raises on a duplicate name. *)
let add_spec_def env name declaration =
  { env with spec_defs = add_unique_assoc "spec definition" name declaration env.spec_defs }

(* [enum_members env name] resolves [name] to its constructor list.
   It raises an elaboration error when [name] is not a known enum. *)
let enum_members env name =
  match List.assoc_opt name env.enum_sets with
  | Some members -> members
  | None ->
      Kr_lang_shared.Kr_lang_shared_error.elaboration
        (Printf.sprintf "unknown enum type '%s'" name)

(* [expand_enum_or_single env name] expands an enum name to its constructors;
   an ordinary index name is returned as a singleton list. *)
let expand_enum_or_single env name =
  match List.assoc_opt name env.enum_sets with Some members -> members | None -> [ name ]

(* [cartesian_concat left right] implements the internal cartesian concat operation. It returns the operation result. *)
let cartesian_concat left right =
  List.concat_map (fun xs -> List.map (fun ys -> xs @ ys) right) left

(* [expand_index_product env atoms] computes the Cartesian product of the
   choices represented by [atoms]. *)
let expand_index_product env atoms =
  List.fold_right
    (fun atom acc ->
      let choices = List.map (fun name -> [ name ]) (expand_enum_or_single env atom) in
      cartesian_concat choices acc)
    atoms [ [] ]

(* [expand_index_choices env choices] expands all indexed declaration
   dimensions into their concrete index combinations. *)
let expand_index_choices env choices =
  List.concat_map (expand_index_product env) choices

(* [lower_raw_vdecl env raw] flattens one possibly indexed declaration into
   scalar core declarations. *)
let lower_raw_vdecl env (raw : S.raw_vdecl) : vdecl list =
  match raw.raw_indices with
  | None -> [ { vname = raw.raw_vname; vty = raw.raw_vty } ]
  | Some choices ->
      expand_index_choices env choices
      |> List.map (fun idxs ->
             { vname = Names.indexed_ident_many raw.raw_vname idxs; vty = raw.raw_vty })

(* [lower_raw_vdecls env raws] flattens every declaration in [raws],
   preserving declaration and index order. *)
let lower_raw_vdecls env raws = List.concat_map (lower_raw_vdecl env) raws

(* [range_values lo hi] enumerates the inclusive integer interval; it returns
   the empty list when [lo] is greater than [hi]. *)
let rec range_values lo hi =
  if lo > hi then [] else lo :: range_values (lo + 1) hi

let eval_nat ctx = function
  | S.SNNat n ->
      if n < 0 then
        Kr_lang_shared.Kr_lang_shared_error.well_formedness
          "natural number literal must be non-negative";
      n
  | S.SNVar id -> (
      match List.assoc_opt id ctx.nat_params with
      | Some n -> n
      | None ->
          Kr_lang_shared.Kr_lang_shared_error.elaboration
            (Printf.sprintf "unknown Nat parameter '%s'" id))

(* [function_sig env name] returns the signature registered for [name],
   or [None] when no pure function has that name. *)
let function_sig env name = List.assoc_opt name env.functions

let is_bool_function env name =
  match function_sig env name with Some (_, TBool) -> true | Some _ | None -> false

(* [constructor_type env name] implements the internal constructor type operation. It returns the operation result. *)
let constructor_type env name =
  List.find_map
    (fun (enum_name, constructors) ->
      if List.mem name constructors then Some (TCustom enum_name) else None)
    env.enum_sets

let value_type env name =
  match List.assoc_opt name env.variables with
  | Some ty -> Some ty
  | None -> constructor_type env name

let type_name = function
  | TInt -> "int"
  | TBool -> "bool"
  | TReal -> "real"
  | TCustom name -> name

let validate_type env context = function
  | TInt | TBool | TReal -> ()
  | TCustom name when List.mem_assoc name env.enum_sets -> ()
  | TCustom name ->
      Kr_lang_shared.Kr_lang_shared_error.elaboration
        (Printf.sprintf "%s uses unknown type '%s'" context name)
