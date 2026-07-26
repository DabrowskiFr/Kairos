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

type atom_binding = {
  atom : Core_syntax.ltl_atom;
  name : Core_syntax.ident;
}
[@@deriving yojson]

type request = {
  protocol_version : Tool_protocol.version;
  formula : Core_syntax.ltl;
  atoms : atom_binding list;
}
[@@deriving yojson]

type state_kind =
  | Accepting
  | Rejecting
[@@deriving yojson]

type edge = {
  source : int;
  guard : Core_syntax.hexpr;
  target : int;
}
[@@deriving yojson]

type automaton = {
  initial_state : int;
  states : state_kind list;
  transitions : edge list;
}
[@@deriving yojson]

type response = {
  protocol_version : Tool_protocol.version;
  automaton : automaton;
}
[@@deriving yojson]

let make_request ~atom_map formula =
  {
    protocol_version = Tool_protocol.current_version;
    formula;
    atoms = List.map (fun (atom, name) -> { atom; name }) atom_map;
  }

let make_response automaton =
  { protocol_version = Tool_protocol.current_version; automaton }

let validate_request (request : request) =
  match Tool_protocol.validate ~component:"automata request" request.protocol_version with
  | Error _ as error -> error
  | Ok () ->
      let names = List.map (fun binding -> binding.name) request.atoms in
      if List.length names = List.length (List.sort_uniq String.compare names) then Ok ()
      else Error "automata request contains duplicate atom names"

let validate_response (response : response) =
  match Tool_protocol.validate ~component:"automata response" response.protocol_version with
  | Error _ as error -> error
  | Ok () ->
      let state_count = List.length response.automaton.states in
      let valid_index index = index >= 0 && index < state_count in
      if state_count = 0 then Error "automata response contains no state"
      else if response.automaton.initial_state <> 0 then
        Error "automata response is not canonical: initial state must have index 0"
      else
        match
          List.find_opt
            (fun edge ->
              not (valid_index edge.source && valid_index edge.target))
            response.automaton.transitions
        with
        | None -> Ok ()
        | Some edge ->
            Error
              (Printf.sprintf
                 "automata response contains an out-of-range edge %d -> %d"
                 edge.source edge.target)
