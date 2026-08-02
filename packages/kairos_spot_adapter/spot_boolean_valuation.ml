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
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *---------------------------------------------------------------------------*)

module Automata_exchange = Kairos_automata_contract.Automata_exchange

type term = (string * bool option) list

let conjunction = function
  | [] -> Automata_exchange.Guard_true
  | first :: rest ->
      List.fold_left
        (fun accumulator next -> Automata_exchange.Guard_and (accumulator, next))
        first rest

let disjunction = function
  | [] -> Automata_exchange.Guard_false
  | first :: rest ->
      List.fold_left
        (fun accumulator next -> Automata_exchange.Guard_or (accumulator, next))
        first rest

let term_to_guard term =
  List.filter_map
    (fun (name, value) ->
      match value with
      | None -> None
      | Some true -> Some (Automata_exchange.Guard_atom name)
      | Some false -> Some (Automata_exchange.Guard_not (Automata_exchange.Guard_atom name)))
    term
  |> conjunction

let terms_to_guard terms =
  if terms = [] then Automata_exchange.Guard_false
  else if List.exists (List.for_all (fun (_, value) -> value = None)) terms then
    Automata_exchange.Guard_true
  else List.map term_to_guard terms |> disjunction
