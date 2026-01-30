(*---------------------------------------------------------------------------
 * Tempo - synchronous runtime for OCaml
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
open Specs
open Time_shit

let succ_requires_by_state (n:user_node) : (ident, fo list) Hashtbl.t =
  (* Index successor requires by source state for quick lookup per dst. *)
  let tbl : (ident, fo list) Hashtbl.t = Hashtbl.create 16 in
  List.iter
    (fun (t:transition) ->
      List.iter
        (fun f ->
          let existing =
            Hashtbl.find_opt tbl t.src
            |> Option.value ~default:[]
          in
          Hashtbl.replace tbl t.src (f :: existing))
        t.requires)
    n.trans;
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
        Hashtbl.find_opt succ_requires_by_state t.dst
        |> Option.value ~default:[]
        |> uniq
      in
      let ensures_all = t.ensures in
      let new_ensures =
        match conj_fo ensures_all with
        | None -> []
        | Some ensures_conj ->
            let shifted_req req =
              shift_fo_backward_inputs ~is_input req
            in
            let has_ensure f =
              List.exists (fun f' -> f' = f) t.ensures
            in
            succ_reqs
            |> List.map (fun req -> FImp (ensures_conj, shifted_req req))
            |> List.filter (fun f -> not (has_ensure f))
      in
      if new_ensures = [] then t
      else { t with ensures = t.ensures @ new_ensures })
    trans

let ensure_next_requires (n:user_node) : internal_node =
  let succ_requires_by_state = succ_requires_by_state n in
  let is_input v = List.exists (fun vi -> vi.vname = v) n.inputs in
  let trans =
    updated_transitions ~is_input ~succ_requires_by_state n.trans
  in
  { n with trans }
