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

let normalize_spot_automaton ~(atom_names : string list) (hoa : Automaton_spot.hoa_automaton) :
    Automata_exchange.automaton =
  let rejecting =
    hoa.states
    |> List.filter (fun (state : Automaton_spot.hoa_state) -> not state.accepting)
    |> List.map (fun (state : Automaton_spot.hoa_state) -> state.id)
    |> List.sort_uniq compare
  in
  let has_bad = rejecting <> [] in
  let accepting_ids =
    hoa.states
    |> List.filter (fun (state : Automaton_spot.hoa_state) -> state.accepting)
    |> List.map (fun (state : Automaton_spot.hoa_state) -> state.id)
    |> List.sort_uniq compare
  in
  let ordered_accepting =
    if List.mem hoa.start accepting_ids then
      hoa.start :: List.filter (( <> ) hoa.start) accepting_ids
    else accepting_ids
  in
  let states =
    if has_bad && List.mem hoa.start rejecting then [ Automata_exchange.Rejecting ]
    else
      let accepting = List.map (fun _ -> Automata_exchange.Accepting) ordered_accepting in
      if has_bad then accepting @ [ Automata_exchange.Rejecting ] else accepting
  in
  let bad_index = if has_bad then List.length states - 1 else -1 in
  let state_indices = Hashtbl.create (List.length hoa.states * 2) in
  List.iteri (fun index id -> Hashtbl.replace state_indices id index) ordered_accepting;
  List.iter
    (fun id -> if has_bad && List.mem id rejecting then Hashtbl.replace state_indices id bad_index)
    rejecting;
  let transitions = ref [] in
  let add source guard target =
    transitions := { Automata_exchange.source; guard; target } :: !transitions
  in
  List.iter
    (fun (state : Automaton_spot.hoa_state) ->
      if not (has_bad && List.mem state.id rejecting) then
        let source = Hashtbl.find state_indices state.id in
        List.iter
          (fun (label, old_target) ->
            let target = Hashtbl.find state_indices old_target in
            let raw_guard =
              Automaton_spot.raw_guard_of_label ~atom_names ~hoa_ap_names:hoa.ap_names label
            in
            if raw_guard <> [] then
              add source (Spot_boolean_valuation.terms_to_guard raw_guard) target)
          state.transitions)
    hoa.states;
  if has_bad then add bad_index Automata_exchange.Guard_true bad_index;
  { Automata_exchange.initial_state = 0; states; transitions = List.rev !transitions }

let build ?(record_elapsed = ignore) (request : Automata_exchange.request) :
    Automata_exchange.response =
  (match Automata_exchange.validate_request request with
  | Ok () -> ()
  | Error message -> invalid_arg message);
  let formula = Automaton_spot.string_of_spot_ltl ~atom_names:request.atoms request.formula in
  Automaton_spot.ensure_safety ~record_elapsed formula;
  let hoa = Automaton_spot.call_spot ~record_elapsed formula |> Automaton_spot.parse_hoa in
  if hoa.ap_count <> List.length request.atoms then
    failwith
      (Printf.sprintf "Spot returned %d atomic propositions; expected %d" hoa.ap_count
         (List.length request.atoms));
  normalize_spot_automaton ~atom_names:request.atoms hoa
  |> Automata_exchange.make_response ~atoms:request.atoms
