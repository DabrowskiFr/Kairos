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

open Ast
open Fo_specs
open Fo_time

let succ_requires_by_state (n:node) : (ident, fo list) Hashtbl.t =
  (* Index successor requires by source state for quick lookup per dst. *)
  let tbl : (ident, fo list) Hashtbl.t = Hashtbl.create 16 in
  List.iter
    (fun (t:transition) ->
      List.iter
        (fun f ->
          let existing =
            Hashtbl.find_opt tbl (t.src)
            |> Option.value ~default:[]
          in
          Hashtbl.replace tbl (t.src) (f :: existing))
        (Ast_provenance.values (t.requires)))
    (n.trans);
  tbl

let updated_transitions ~(is_input:ident -> bool)
  ~(succ_requires_by_state:(ident, fo list) Hashtbl.t)
  (trans:transition list) : transition list =
  (* Add ensures derived from successor requires. *)
  let uniq lst =
    List.sort_uniq compare lst
  in
  List.map
    (fun (t:transition) ->
      let succ_reqs =
        Hashtbl.find_opt succ_requires_by_state (t.dst)
        |> Option.value ~default:[]
        |> uniq
      in
      let ensures_all = Ast_provenance.values (t.ensures) in
      let new_ensures =
        match conj_fo ensures_all with
        | None -> []
        | Some ensures_conj ->
            let shifted_req req =
              shift_fo_backward_inputs ~is_input req
            in
            let has_ensure f =
              List.exists (fun f' -> f' = f) ensures_all
            in
            succ_reqs
            |> List.map (fun req -> FImp (ensures_conj, shifted_req req))
            |> List.filter (fun f -> not (has_ensure f))
      in
      if new_ensures = [] then t
      else
        let new_ensures_o =
          List.map (Ast_provenance.with_origin Coherency) new_ensures
        in
        { t with
          ensures = t.ensures @ new_ensures_o; })
    trans

let ensure_next_requires (n:Ast.node) : Ast.node =
  let succ_requires_by_state = succ_requires_by_state n in
  let is_input v = List.exists (fun vi -> vi.vname = v) (n.inputs) in
  let trans =
    updated_transitions ~is_input ~succ_requires_by_state (n.trans)
  in
  { n with trans }

let user_contracts_coherency (n:Ast.node) : Ast.node =
  let is_input v = List.exists (fun vi -> vi.vname = v) (n.inputs) in
  let trans_indexed = List.mapi (fun i t -> (i, t)) (n.trans) in
  let by_src = Hashtbl.create 16 in
  List.iter
    (fun (i, t) ->
       let lst =
         Hashtbl.find_opt by_src (t.src) |> Option.value ~default:[]
       in
       Hashtbl.replace by_src (t.src) (i :: lst))
    trans_indexed;
  let user_requires =
    Array.of_list
      (List.map (fun (t:transition) -> Ast_provenance.values (t.requires))
         (n.trans))
  in
  let user_ensures =
    Array.of_list
      (List.map (fun (t:transition) -> Ast_provenance.values (t.ensures))
         (n.trans))
  in
  let shift_req f = shift_fo_backward_inputs ~is_input f in
  let add_coherency (i:int) (t:transition) =
    match conj_fo user_ensures.(i) with
    | None -> t
    | Some ens_conj ->
        let next =
          Hashtbl.find_opt by_src (t.dst) |> Option.value ~default:[]
        in
        let new_ensures =
          List.concat_map
            (fun j ->
               List.map (fun r -> FImp (ens_conj, shift_req r)) user_requires.(j))
            next
        in
        if new_ensures = [] then t
        else
          let new_ensures_o =
            List.map (Ast_provenance.with_origin Coherency) new_ensures
          in
          { t with
            ensures = t.ensures @ new_ensures_o }
  in
  let trans =
    List.map (fun (i, t) -> add_coherency i t) trans_indexed
  in
  { n with trans }
