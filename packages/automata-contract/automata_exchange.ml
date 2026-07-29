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

type atom = string [@@deriving yojson]

type ltl =
  | True
  | False
  | Atom of atom
  | Not of ltl
  | And of ltl * ltl
  | Or of ltl * ltl
  | Implies of ltl * ltl
  | Next of ltl
  | Always of ltl
  | Weak_until of ltl * ltl
[@@deriving yojson]

type guard =
  | Guard_true
  | Guard_false
  | Guard_atom of atom
  | Guard_not of guard
  | Guard_and of guard * guard
  | Guard_or of guard * guard
[@@deriving yojson]

type request = { protocol_version : int; atoms : atom list; formula : ltl } [@@deriving yojson]
type edge = { source : int; guard : guard; target : int } [@@deriving yojson]

type partial_monitor = { initial_state : int; state_count : int; transitions : edge list }
[@@deriving yojson]

type response = { protocol_version : int; atoms : atom list; monitor : partial_monitor }
[@@deriving yojson]

let current_protocol_version = 2
let make_request ~atoms formula = { protocol_version = current_protocol_version; atoms; formula }
let make_response ~atoms monitor = { protocol_version = current_protocol_version; atoms; monitor }

let rec atoms_of_ltl = function
  | True | False -> []
  | Atom atom -> [ atom ]
  | Not formula | Next formula | Always formula -> atoms_of_ltl formula
  | And (left, right) | Or (left, right) | Implies (left, right) | Weak_until (left, right) ->
      atoms_of_ltl left @ atoms_of_ltl right |> List.sort_uniq String.compare

let rec atoms_of_guard = function
  | Guard_true | Guard_false -> []
  | Guard_atom atom -> [ atom ]
  | Guard_not guard -> atoms_of_guard guard
  | Guard_and (left, right) | Guard_or (left, right) ->
      atoms_of_guard left @ atoms_of_guard right |> List.sort_uniq String.compare

let validate_version component version =
  if version = current_protocol_version then Ok ()
  else
    Error
      (Printf.sprintf "%s protocol version %d is unsupported; expected %d" component version
         current_protocol_version)

let validate_atoms component declared referenced =
  if List.exists (String.equal "") declared then Error (component ^ " contains an empty atom name")
  else if List.length declared <> List.length (List.sort_uniq String.compare declared) then
    Error (component ^ " contains duplicate atom names")
  else
    match List.find_opt (fun atom -> not (List.mem atom declared)) referenced with
    | Some atom -> Error (Printf.sprintf "%s references undeclared atom %S" component atom)
    | None -> Ok ()

let validate_request (request : request) =
  match validate_version "automata request" request.protocol_version with
  | Error _ as error -> error
  | Ok () -> validate_atoms "automata request" request.atoms (atoms_of_ltl request.formula)

let validate_response (response : response) =
  match validate_version "automata response" response.protocol_version with
  | Error _ as error -> error
  | Ok () -> (
      let referenced =
        List.concat_map (fun edge -> atoms_of_guard edge.guard) response.monitor.transitions
        |> List.sort_uniq String.compare
      in
      match validate_atoms "automata response" response.atoms referenced with
      | Error _ as error -> error
      | Ok () -> (
          let monitor = response.monitor in
          let state_count = monitor.state_count in
          let valid_index index = index >= 0 && index < state_count in
          if state_count <= 0 then Error "automata response contains no state"
          else if not (valid_index monitor.initial_state) then
            Error "automata response contains an out-of-range initial state"
          else
            match
              List.find_opt
                (fun edge -> not (valid_index edge.source && valid_index edge.target))
                monitor.transitions
            with
            | None -> Ok ()
            | Some edge ->
                Error
                  (Printf.sprintf "automata response contains an out-of-range edge %d -> %d"
                     edge.source edge.target)))
