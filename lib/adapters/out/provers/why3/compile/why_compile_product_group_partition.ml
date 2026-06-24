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
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *---------------------------------------------------------------------------*)

type entry = Why_compile_product_group_boundary.entry

type t = { entries : entry list }

let entries group = group.entries

let group_key (_i, (sc : Why_contracts.step_contract_info), transition) =
  (sc.step.step_class, transition)

let partition entries =
  let groups = Hashtbl.create 128 in
  let order = ref [] in
  List.iter
    (fun entry ->
      let key = group_key entry in
      if not (Hashtbl.mem groups key) then order := key :: !order;
      let previous = Hashtbl.find_opt groups key |> Option.value ~default:[] in
      Hashtbl.replace groups key (entry :: previous))
    entries;
  List.rev !order
  |> List.map (fun key ->
         { entries = Hashtbl.find groups key |> List.rev })
