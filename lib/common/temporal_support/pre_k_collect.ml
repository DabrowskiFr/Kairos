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
open Ast_builders
open Temporal_support

let rec collect_hexpr (h : hexpr) (acc : hexpr list) : hexpr list =
  let acc =
    match h.hexpr with HPreK _ -> if List.exists (fun h' -> h' = h) acc then acc else h :: acc | _ -> acc
  in
  match h.hexpr with
  | HLitInt _ | HLitBool _ | HVar _ | HPreK _ -> acc
  | HUn (_, inner) -> collect_hexpr inner acc
  | HArithBin (_, a, b) | HBoolBin (_, a, b) | HCmp (_, a, b) ->
      collect_hexpr b (collect_hexpr a acc)

let rec collect_ltl (f : ltl) (acc : hexpr list) : hexpr list =
  match f with
  | LTrue | LFalse -> acc
  | LNot a -> collect_ltl a acc
  | LAnd (a, b) | LOr (a, b) | LImp (a, b) | LW (a, b) -> collect_ltl b (collect_ltl a acc)
  | LX a | LG a -> collect_ltl a acc
  | LAtom f -> collect_fo f acc

and collect_fo (f : fo_atom) (acc : hexpr list) : hexpr list =
  match f with
  | FRel (h1, _, h2) -> collect_hexpr h2 (collect_hexpr h1 acc)
  | FPred (_id, hs) -> List.fold_left (fun a h -> collect_hexpr h a) acc hs

let collect_pre_k_from_specs ~(fo_formula : Fo_formula.t list) ~(ltl : ltl list) : hexpr list =
  let collect_pre_k_hexpr = collect_hexpr in
  let rec collect_pre_k_ltl f acc =
    match f with
    | LTrue | LFalse -> acc
    | LNot a | LX a | LG a -> collect_pre_k_ltl a acc
    | LAnd (a, b) | LOr (a, b) | LImp (a, b) | LW (a, b) ->
        collect_pre_k_ltl b (collect_pre_k_ltl a acc)
    | LAtom f -> collect_pre_k_fo f acc
  and collect_pre_k_fo f acc =
    match f with
    | FRel (h1, _, h2) -> collect_pre_k_hexpr h2 (collect_pre_k_hexpr h1 acc)
    | FPred (_id, hs) -> List.fold_left (fun a h -> collect_pre_k_hexpr h a) acc hs
  in
  let rec collect_pre_k_fo_formula (f : Fo_formula.t) (acc : hexpr list) : hexpr list =
    match f with
    | Fo_formula.FTrue | Fo_formula.FFalse -> acc
    | Fo_formula.FAtom atom -> collect_pre_k_fo atom acc
    | Fo_formula.FNot inner -> collect_pre_k_fo_formula inner acc
    | Fo_formula.FAnd (a, b) | Fo_formula.FOr (a, b) | Fo_formula.FImp (a, b) ->
        collect_pre_k_fo_formula b (collect_pre_k_fo_formula a acc)
  in
  let acc = List.fold_left (fun acc f -> collect_pre_k_fo_formula f acc) [] fo_formula in
  List.fold_left (fun acc f -> collect_pre_k_ltl f acc) acc ltl

let build_pre_k_infos_from_parts ~(inputs : vdecl list) ~(locals : vdecl list) ~(outputs : vdecl list)
    ~(fo_formulas : Fo_formula.t list) ~(ltl : ltl list) :
    (hexpr * Temporal_support.pre_k_info) list =
  let init_for_var =
    let table =
      List.map (fun v -> (v.vname, v.vty)) (inputs @ locals @ outputs)
    in
    fun v ->
      match List.assoc_opt v table with
      | Some TBool -> mk_bool false
      | Some TInt -> mk_int 0
      | Some TReal -> mk_int 0
      | Some (TCustom _) | None -> mk_int 0
  in
  let normalize_ltl f = (normalize_ltl_for_k ~init_for_var f).ltl in
  let normalized_ltl = List.map normalize_ltl ltl in
  let pre_k_exprs = collect_pre_k_from_specs ~fo_formula:fo_formulas ~ltl:normalized_ltl in
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
      (fun acc h ->
        match h.hexpr with
        | HPreK (vname, k) ->
            let current = Option.value (List.assoc_opt vname acc) ~default:0 in
            if k > current then (vname, k) :: List.remove_assoc vname acc else acc
        | _ -> acc)
      [] pre_k_exprs
  in
  pre_k_exprs
  |> List.mapi (fun i h ->
         let _ = i in
         match h.hexpr with
         | HPreK (vname, k) ->
             if k <= 0 then failwith "pre_k expects k >= 1";
             let vty = find_vty vname in
             let names =
               match List.assoc_opt vname max_k_by_var with
               | Some max_k -> make_names vname max_k
               | None -> failwith ("pre_k missing max depth for variable: " ^ vname)
             in
             (h, { h; expr = mk_var vname; names; vty })
         | _ -> failwith "expected pre_k hexpr")

let build_pre_k_infos (n : node) : (hexpr * Temporal_support.pre_k_info) list =
  let spec = specification_of_node n in
  let sem = semantics_of_node n in
  build_pre_k_infos_from_parts ~inputs:sem.sem_inputs ~locals:sem.sem_locals ~outputs:sem.sem_outputs
    ~fo_formulas:(List.map (fun inv -> inv.formula) spec.spec_invariants_state_rel)
    ~ltl:(spec.spec_assumes @ spec.spec_guarantees)

let extract_delay_spec (guarantees : ltl list) : (ident * ident) option =
  let rec find_in_ltl = function
    | LG a -> find_in_ltl a
    | LX a -> find_in_ltl a
    | LAtom (FRel (lhs, REq, rhs)) -> (
        match (lhs.hexpr, rhs.hexpr) with
        | HVar out, HPreK (b, 1) -> Some (out, b)
        | HPreK (b, 1), HVar out -> Some (out, b)
        | _ -> None)
    | _ -> None
  in
  List.find_map find_in_ltl guarantees
