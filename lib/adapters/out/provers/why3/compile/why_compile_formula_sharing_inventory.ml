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
open Core_syntax
open Why_compile_expr
open Why_compile_logic

module StringSet = Why_compile_ptree_helpers.StringSet

type shared_entry = string * (Core_syntax.ident * Ptree.pty) list * int * bool

type selection = {
  table : (string, shared_entry) Hashtbl.t;
  order :
    (string * (Core_syntax.ident * Ptree.pty) list * Core_syntax.hexpr * int)
    list;
}

let formula_key (formula : Core_syntax.hexpr) =
  Core_fo_simplifier.key_of_hexpr formula

let is_composite_fact (formula : Core_syntax.hexpr) =
  match formula.hexpr with
  | HBin (And, _, _) | HBin (Or, _, _) | HUn (Not, _) | HPred _ -> true
  | HLitInt _ | HLitBool _ | HLitEnum _ | HVar _ | HPreK _ | HFunCall _
  | HUn (Neg, _)
  | HBin ((Add | Sub | Mul | Div), _, _)
  | HCmp _ ->
      false

let shared_formula_params env inputs =
  inputs
  |> List.filter_map (fun (_, id_opt, _, pty_opt) ->
         match (id_opt, pty_opt) with
         | Some id, Some pty when not (String.equal id.id_str env.rec_name) ->
             Some (id.id_str, pty)
         | _ -> None)

let params_for_formula shared_params (formula : Core_syntax.hexpr) =
  let vars = vars_of_hexpr StringSet.empty formula in
  List.filter (fun (param_name, _) -> StringSet.mem param_name vars) shared_params

let formula_uses_self env (formula : Core_syntax.hexpr) =
  let vars = vars_of_hexpr StringSet.empty formula in
  List.exists (fun rec_var -> StringSet.mem rec_var vars) env.rec_vars

let record_formula_occurrence stats ~scope (formula : Core_syntax.hexpr) =
  let key = formula_key formula in
  match Hashtbl.find_opt stats key with
  | Some (representative, count, scopes) ->
      Hashtbl.replace stats key
        (representative, count + 1, StringSet.add scope scopes)
  | None ->
      Hashtbl.add stats key (formula, 1, StringSet.singleton scope)

let add_summary_formulas stats ~scope formulas =
  List.iter
    (fun (formula : Ir.summary_formula) ->
      record_formula_occurrence stats ~scope formula.logic)
    formulas

let record_product_formulas stats (runtime_view : Why_runtime_view.t) =
  runtime_view.product_transitions
  |> List.iteri (fun idx (pc : Why_runtime_view.runtime_product_transition_view) ->
         let scope =
           Printf.sprintf "%d:%s:%s:%d:%d:%s" idx pc.transition_id
             pc.product_src.prog_state pc.product_src.assume_state_index
             pc.product_src.guarantee_state_index
             (match pc.step_class with
             | Why_runtime_view.StepSafe -> "safe"
             | Why_runtime_view.StepBadGuarantee -> "bad_guarantee")
         in
         add_summary_formulas stats ~scope pc.requires;
         add_summary_formulas stats ~scope pc.local_requires;
         (* Forbidden facts are emitted transparently under negation. Recording
            them here would create shared predicates that the proof path no
            longer calls. *)
         add_summary_formulas stats ~scope pc.ensures;
         add_summary_formulas stats ~scope pc.elaboration_checks)

let select_shared_formulas env shared_params stats table order =
  Hashtbl.to_seq stats
  |> Seq.iter (fun (key, (formula, _count, scopes)) ->
         if is_composite_fact formula && StringSet.cardinal scopes > 1 then (
           let size = hexpr_size formula in
           let name =
             Printf.sprintf "shared_contract_formula_%03d"
               (Hashtbl.length table + 1)
           in
           let params = params_for_formula shared_params formula in
           let use_self = formula_uses_self env formula in
           Hashtbl.add table key (name, params, size, use_self);
           order := (name, params, formula, size) :: !order))

let select ~env ~inputs ~runtime_view =
  let stats : (string, Core_syntax.hexpr * int * StringSet.t) Hashtbl.t =
    Hashtbl.create 128
  in
  let table : (string, shared_entry) Hashtbl.t = Hashtbl.create 128 in
  let order = ref [] in
  record_product_formulas stats runtime_view;
  select_shared_formulas env (shared_formula_params env inputs) stats table order;
  { table; order = !order }
