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

open Ast
open Ast_builders
open Generated_names
open Temporal_support
open Ast_pretty

let rec collect_hexpr (h : hexpr) (acc : hexpr list) : hexpr list =
  let acc = if List.exists (fun h' -> h' = h) acc then acc else h :: acc in
  match h with HNow _ -> acc | HPreK (e, _) -> collect_hexpr (HNow e) acc

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

let collect_pre_k_from_specs ~(fo_atom : ltl list) ~(ltl : ltl list)
    ~(invariants_user : invariant_user list) ~(invariants_state_rel : invariant_state_rel list) :
    hexpr list =
  let collect_pre_k_hexpr h acc =
    let acc =
      match h with HPreK _ -> if List.exists (( = ) h) acc then acc else h :: acc | _ -> acc
    in
    match h with HNow _ | HPreK _ -> acc
  in
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
  let acc = List.fold_left (fun acc f -> collect_pre_k_ltl f acc) [] fo_atom in
  let acc = List.fold_left (fun acc f -> collect_pre_k_ltl f acc) acc ltl in
  List.fold_left (fun acc inv -> collect_pre_k_hexpr inv.inv_expr acc) acc invariants_user
  |> fun acc ->
  List.fold_left (fun acc inv -> collect_pre_k_ltl inv.formula acc) acc invariants_state_rel

let build_pre_k_infos_from_parts ~(inputs : vdecl list) ~(locals : vdecl list) ~(outputs : vdecl list)
    ~(ltl : ltl list) ~(invariants_user : invariant_user list)
    ~(invariants_state_rel : invariant_state_rel list) :
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
  let coherency_fo = [] in
  let normalized_fo = List.map normalize_ltl coherency_fo in
  let normalized_ltl = List.map normalize_ltl ltl in
  let normalized_invariants_user = invariants_user in
  let normalized_invariants_state_rel =
    List.map
      (fun inv -> { inv with formula = normalize_ltl inv.formula })
      invariants_state_rel
  in
  let pre_k_exprs =
    collect_pre_k_from_specs ~fo_atom:normalized_fo ~ltl:normalized_ltl
      ~invariants_user:normalized_invariants_user
      ~invariants_state_rel:normalized_invariants_state_rel
  in
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
        match h with
        | HPreK ({ iexpr = IVar vname; _ }, k) ->
            let current = Option.value (List.assoc_opt vname acc) ~default:0 in
            if k > current then (vname, k) :: List.remove_assoc vname acc else acc
        | HPreK _ -> failwith "pre_k expects a variable as first argument"
        | _ -> acc)
      [] pre_k_exprs
  in
  pre_k_exprs
  |> List.mapi (fun i h ->
         let _ = i in
         match h with
         | HPreK (e, k) ->
             if k <= 0 then failwith "pre_k expects k >= 1";
             let vname =
               match e.iexpr with
               | IVar x -> x
               | _ -> failwith "pre_k expects a variable as first argument"
             in
             let vty = find_vty vname in
             let names =
               match List.assoc_opt vname max_k_by_var with
               | Some max_k -> make_names vname max_k
               | None -> failwith ("pre_k missing max depth for variable: " ^ vname)
             in
             (h, { h; expr = e; names; vty })
         | _ -> failwith "expected pre_k hexpr")

let build_pre_k_infos (n : node) : (hexpr * Temporal_support.pre_k_info) list =
  let spec = specification_of_node n in
  let sem = semantics_of_node n in
  build_pre_k_infos_from_parts ~inputs:sem.sem_inputs ~locals:sem.sem_locals ~outputs:sem.sem_outputs
    ~ltl:(spec.spec_assumes @ spec.spec_guarantees) ~invariants_user:[]
    ~invariants_state_rel:spec.spec_invariants_state_rel

let rec collect_calls_stmt (acc : (ident * iexpr list) list) (s : stmt) : (ident * iexpr list) list
    =
  match s.stmt with
  | SCall (inst, args, _outs) -> (inst, args) :: acc
  | SIf (_c, tbr, fbr) ->
      let acc = List.fold_left collect_calls_stmt acc tbr in
      List.fold_left collect_calls_stmt acc fbr
  | SMatch (_e, branches, def) ->
      let acc =
        List.fold_left
          (fun acc (_ctor, body) -> List.fold_left collect_calls_stmt acc body)
          acc branches
      in
      List.fold_left collect_calls_stmt acc def
  | SAssign _ | SSkip -> acc

let collect_calls_trans (ts : transition list) : (ident * iexpr list) list =
  List.fold_left
    (fun acc (t : transition) ->
      let acc = List.fold_left collect_calls_stmt acc t.body in
      acc)
    [] ts

let rec collect_calls_stmt_full (acc : (ident * iexpr list * ident list) list) (s : stmt) :
    (ident * iexpr list * ident list) list =
  match s.stmt with
  | SCall (inst, args, outs) -> (inst, args, outs) :: acc
  | SIf (_c, tbr, fbr) ->
      let acc = List.fold_left collect_calls_stmt_full acc tbr in
      List.fold_left collect_calls_stmt_full acc fbr
  | SMatch (_e, branches, def) ->
      let acc =
        List.fold_left
          (fun acc (_ctor, body) -> List.fold_left collect_calls_stmt_full acc body)
          acc branches
      in
      List.fold_left collect_calls_stmt_full acc def
  | SAssign _ | SSkip -> acc

let collect_calls_trans_full (ts : transition list) : (ident * iexpr list * ident list) list =
  List.fold_left
    (fun acc (t : transition) ->
      let acc = List.fold_left collect_calls_stmt_full acc t.body in
      acc)
    [] ts

let extract_delay_spec (guarantees : ltl list) : (ident * ident) option =
  let rec find_in_ltl = function
    | LG a -> find_in_ltl a
    | LX a -> find_in_ltl a
    | LAtom (FRel (HNow a, REq, HPreK (b, 1))) | LAtom (FRel (HPreK (b, 1), REq, HNow a)) -> begin
        match (as_var a, as_var b) with Some out, Some inp -> Some (out, inp) | _ -> None
      end
    | _ -> None
  in
  List.find_map find_in_ltl guarantees
