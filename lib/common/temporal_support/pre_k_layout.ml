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
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *---------------------------------------------------------------------------*)

[@@@ocaml.warning "-8-26-27-32-33"]
open Core_syntax
open Ast

type pre_k_info = {
  var_name : Core_syntax.ident;
  names : string list;
  vty : Core_syntax.ty;
}
[@@deriving yojson]

let add_pre_k_occurrence (vname : ident) (k : int) (acc : (ident * int) list) : (ident * int) list =
  if List.exists (fun (v, d) -> String.equal v vname && d = k) acc then acc else (vname, k) :: acc

let rec collect_pre_k_occurrences_hexpr (h : Core_syntax.hexpr) (acc : (ident * int) list) :
    (ident * int) list =
  match h.hexpr with
  | HLitInt _ | HLitBool _ | HVar _ -> acc
  | HPreK (vname, k) -> add_pre_k_occurrence vname k acc
  | HPred (_, hs) -> List.fold_left (fun a x -> collect_pre_k_occurrences_hexpr x a) acc hs
  | HUn (_, inner) -> collect_pre_k_occurrences_hexpr inner acc
  | HBin (_, a, b) | HCmp (_, a, b) ->
      collect_pre_k_occurrences_hexpr b (collect_pre_k_occurrences_hexpr a acc)

let rec collect_pre_k_occurrences_ltl (f : ltl) (acc : (ident * int) list) : (ident * int) list =
  match f with
  | LTrue | LFalse -> acc
  | LNot a | LX a | LG a -> collect_pre_k_occurrences_ltl a acc
  | LAnd (a, b) | LOr (a, b) | LImp (a, b) | LW (a, b) ->
      collect_pre_k_occurrences_ltl b (collect_pre_k_occurrences_ltl a acc)
  | LAtom (h1, _, h2) ->
      collect_pre_k_occurrences_hexpr h2 (collect_pre_k_occurrences_hexpr h1 acc)

let collect_pre_k_from_specs ~(fo_formula : Core_syntax.hexpr list) ~(ltl : ltl list) :
    (ident * int) list =
  let acc = List.fold_left (fun acc f -> collect_pre_k_occurrences_hexpr f acc) [] fo_formula in
  List.fold_left (fun acc f -> collect_pre_k_occurrences_ltl f acc) acc ltl

let build_pre_k_infos_from_parts ~(inputs : vdecl list) ~(locals : vdecl list) ~(outputs : vdecl list)
    ~(fo_formulas : Core_syntax.hexpr list) ~(ltl : ltl list) :
    pre_k_info list =
  let pre_k_occurrences = collect_pre_k_from_specs ~fo_formula:fo_formulas ~ltl in
  let vars = inputs @ locals @ outputs in
  let find_vty name =
    match List.find_opt (fun v -> v.vname = name) vars with
    | Some v -> v.vty
    | None -> failwith ("pre_k unknown variable: " ^ name)
  in
  let make_names vname k =
    let rec loop acc i =
      if i > k then List.rev acc else loop (Printf.sprintf "__pre_k%d_%s" i vname :: acc) (i + 1)
    in
    loop [] 1
  in
  let max_k_by_var =
    List.fold_left
      (fun acc (vname, k) ->
        let current = Option.value (List.assoc_opt vname acc) ~default:0 in
        if k > current then (vname, k) :: List.remove_assoc vname acc else acc)
      [] pre_k_occurrences
  in
  max_k_by_var
  |> List.sort (fun (a, _) (b, _) -> String.compare a b)
  |> List.map (fun (vname, max_k) ->
         if max_k <= 0 then failwith "pre_k expects k >= 1";
         let vty = find_vty vname in
         let names = make_names vname max_k in
         { var_name = vname; names; vty })

let build_pre_k_infos (n : node) : pre_k_info list =
  let spec = specification_of_node n in
  let sem = semantics_of_node n in
  build_pre_k_infos_from_parts ~inputs:sem.sem_inputs ~locals:sem.sem_locals ~outputs:sem.sem_outputs
    ~fo_formulas:(List.map (fun inv -> inv.formula) spec.spec_invariants_state_rel)
    ~ltl:(spec.spec_assumes @ spec.spec_guarantees)
