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
open Support

let rec collect_hexpr (h : hexpr) (acc : hexpr list) : hexpr list =
  let acc = if List.exists (fun h' -> h' = h) acc then acc else h :: acc in
  match h with HNow _ -> acc | HPreK (e, _) -> collect_hexpr (HNow e) acc

let rec collect_ltl (f : fo_ltl) (acc : hexpr list) : hexpr list =
  match f with
  | LTrue | LFalse -> acc
  | LNot a -> collect_ltl a acc
  | LAnd (a, b) | LOr (a, b) | LImp (a, b) | LW (a, b) -> collect_ltl b (collect_ltl a acc)
  | LX a | LG a -> collect_ltl a acc
  | LAtom f -> collect_fo f acc

and collect_fo (f : fo) (acc : hexpr list) : hexpr list =
  match f with
  | FTrue | FFalse -> acc
  | FRel (h1, _, h2) -> collect_hexpr h2 (collect_hexpr h1 acc)
  | FPred (_id, hs) -> List.fold_left (fun a h -> collect_hexpr h a) acc hs
  | FNot a -> collect_fo a acc
  | FAnd (a, b) | FOr (a, b) | FImp (a, b) -> collect_fo b (collect_fo a acc)

let collect_pre_k_from_specs ~(fo : fo list) ~(ltl : fo_ltl list)
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
    | FTrue | FFalse -> acc
    | FRel (h1, _, h2) -> collect_pre_k_hexpr h2 (collect_pre_k_hexpr h1 acc)
    | FPred (_id, hs) -> List.fold_left (fun a h -> collect_pre_k_hexpr h a) acc hs
    | FNot a -> collect_pre_k_fo a acc
    | FAnd (a, b) | FOr (a, b) | FImp (a, b) -> collect_pre_k_fo b (collect_pre_k_fo a acc)
  in
  let acc = List.fold_left (fun acc f -> collect_pre_k_fo f acc) [] fo in
  let acc = List.fold_left (fun acc f -> collect_pre_k_ltl f acc) acc ltl in
  List.fold_left (fun acc inv -> collect_pre_k_hexpr inv.inv_expr acc) acc invariants_user
  |> fun acc ->
  List.fold_left (fun acc inv -> collect_pre_k_fo inv.formula acc) acc invariants_state_rel

let build_pre_k_infos (n : node) : (hexpr * pre_k_info) list =
  let init_for_var =
    let table = List.map (fun v -> (v.vname, v.vty)) (n.inputs @ n.locals @ n.outputs) in
    fun v ->
      match List.assoc_opt v table with
      | Some TBool -> mk_bool false
      | Some TInt -> mk_int 0
      | Some TReal -> mk_int 0
      | Some (TCustom _) | None -> mk_int 0
  in
  let normalize_fo f =
    let normalized = normalize_ltl_for_k ~init_for_var (ltl_of_fo f) in
    fo_of_ltl normalized.ltl
  in
  let normalize_ltl f = (normalize_ltl_for_k ~init_for_var f).ltl in
  let transition_fo =
    List.concat_map
      (fun (t : transition) -> Ast_provenance.values t.requires @ Ast_provenance.values t.ensures)
      n.trans
  in
  let coherency_fo = Ast_provenance.values n.attrs.coherency_goals in
  let normalized_fo = List.map normalize_fo (transition_fo @ coherency_fo) in
  let normalized_ltl = List.map normalize_ltl (n.assumes @ n.guarantees) in
  let normalized_invariants_user = n.attrs.invariants_user in
  let normalized_invariants_state_rel =
    List.map
      (fun inv -> { inv with formula = normalize_fo inv.formula })
      n.attrs.invariants_state_rel
  in
  let pre_k_exprs =
    collect_pre_k_from_specs ~fo:normalized_fo ~ltl:normalized_ltl
      ~invariants_user:normalized_invariants_user
      ~invariants_state_rel:normalized_invariants_state_rel
  in
  let vars = n.inputs @ n.locals @ n.outputs in
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
  pre_k_exprs
  |> List.mapi (fun i h ->
      match h with
      | HPreK (e, k) ->
          if k <= 0 then failwith "pre_k expects k >= 1";
          let vname =
            match e.iexpr with
            | IVar x -> x
            | _ -> failwith "pre_k expects a variable as first argument"
          in
          let vty = find_vty vname in
          let names = make_names vname k in
          (h, { h; expr = e; names; vty })
      | _ -> failwith "expected pre_k hexpr")

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
      let acc = List.fold_left collect_calls_stmt acc t.attrs.ghost in
      let acc = List.fold_left collect_calls_stmt acc t.body in
      List.fold_left collect_calls_stmt acc t.attrs.instrumentation)
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
      let acc = List.fold_left collect_calls_stmt_full acc t.attrs.ghost in
      let acc = List.fold_left collect_calls_stmt_full acc t.body in
      List.fold_left collect_calls_stmt_full acc t.attrs.instrumentation)
    [] ts

let extract_delay_spec (guarantees : fo_ltl list) : (ident * ident) option =
  let rec find_in_ltl = function
    | LG a -> find_in_ltl a
    | LAtom (FRel (HNow a, REq, HPreK (b, 1))) | LAtom (FRel (HPreK (b, 1), REq, HNow a)) -> begin
        match (as_var a, as_var b) with Some out, Some inp -> Some (out, inp) | _ -> None
      end
    | _ -> None
  in
  List.find_map find_in_ltl guarantees
