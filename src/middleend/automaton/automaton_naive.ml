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
open Automaton_atoms
open Automaton_config

let all_valuations (names:string list) : (string * bool) list list =
  let rec aux acc = function
    | [] -> [List.rev acc]
    | n :: rest ->
        let t = aux ((n, true) :: acc) rest in
        let f = aux ((n, false) :: acc) rest in
        t @ f
  in
  aux [] names

let constrained_valuations (atom_map:(fo * ident) list) (names:string list)
  : (string * bool) list list =
  let raw = all_valuations names in
  let eq_atoms = List.filter_map extract_eq_atom atom_map in
  let by_var =
    List.fold_left
      (fun acc a ->
         let existing = List.assoc_opt a.var acc |> Option.value ~default:[] in
         (a.var, a :: existing)
         :: List.remove_assoc a.var acc)
      []
      eq_atoms
  in
  let consistent vals =
    let lookup name =
      match List.assoc_opt name vals with
      | Some true -> true
      | _ -> false
    in
    let check_var atoms =
      let bool_true = List.find_opt (fun a -> a.value = VBool true) atoms in
      let bool_false = List.find_opt (fun a -> a.value = VBool false) atoms in
      match bool_true, bool_false with
      | Some t, Some f ->
          let vt = lookup t.name in
          let vf = lookup f.name in
          (vt && not vf) || (vf && not vt)
      | _ ->
          let trues =
            List.fold_left
              (fun acc a -> if lookup a.name then acc + 1 else acc)
              0
              atoms
          in
          trues <= 1
    in
    List.for_all (fun (_var, atoms) -> check_var atoms) by_var
  in
  let filtered = List.filter consistent raw in
  log_monitor "valuations: raw=%d filtered=%d constraints=%d"
    (List.length raw) (List.length filtered) (List.length by_var);
  filtered
