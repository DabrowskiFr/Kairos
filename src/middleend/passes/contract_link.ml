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
open Time_shit

let conj_fo (fs:fo list) : fo option =
  match fs with
  | [] -> None
  | f :: rest -> Some (List.fold_left (fun acc x -> FAnd (acc, x)) f rest)

let ensure_next_requires (n:user_node) : internal_node =
  let succ_requires_by_state : (ident, fo list) Hashtbl.t = Hashtbl.create 16 in
  List.iter
    (fun (t:transition) ->
      List.iter
        (fun f ->
          let existing =
            Hashtbl.find_opt succ_requires_by_state t.src
            |> Option.value ~default:[]
          in
          Hashtbl.replace succ_requires_by_state t.src (f :: existing))
        t.requires)
    n.trans;
  let uniq lst =
    List.sort_uniq compare lst
  in
  let trans =
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
              let is_input v = List.exists (fun vi -> vi.vname = v) n.inputs in
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
      n.trans
  in
  { n with trans }

let ensure_next_requires_program (p:user_program) : internal_program =
  List.map ensure_next_requires p
