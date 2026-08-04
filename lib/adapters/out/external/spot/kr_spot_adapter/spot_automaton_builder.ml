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

module Automata_exchange = Kr_engine.Kr_engine_automata_contract

let normalize_spot_monitor ~(atom_names : string list) (hoa : Automaton_spot.hoa_automaton) :
    Automata_exchange.partial_monitor =
  if hoa.acceptance <> Automaton_spot.Acceptance_all then
    failwith
      "Spot returned an acceptance condition for a safety monitor; expected a partial \
       all-accepting monitor";
  let state_ids =
    hoa.states
    |> List.map (fun (state : Automaton_spot.hoa_state) -> state.id)
    |> List.sort_uniq compare
  in
  if not (List.mem hoa.start state_ids) then
    failwith "Spot returned a start state that is absent from the HOA body";
  let ordered_states = hoa.start :: List.filter (( <> ) hoa.start) state_ids in
  let state_indices = Hashtbl.create (List.length hoa.states * 2) in
  List.iteri (fun index id -> Hashtbl.replace state_indices id index) ordered_states;
  let transitions = ref [] in
  let add source guard target =
    transitions := { Automata_exchange.source; guard; target } :: !transitions
  in
  List.iter
    (fun (state : Automaton_spot.hoa_state) ->
      let source = Hashtbl.find state_indices state.id in
      List.iter
        (fun (label, old_target) ->
          let target =
            match Hashtbl.find_opt state_indices old_target with
            | Some target -> target
            | None ->
                failwith
                  (Printf.sprintf "Spot returned a transition to undeclared state %d" old_target)
          in
          let raw_guard =
            Automaton_spot.raw_guard_of_label ~atom_names
              ~hoa_ap_names:hoa.ap_names label
          in
          if raw_guard <> [] then
            add source
              (Spot_boolean_valuation.terms_to_guard raw_guard)
              target)
        state.transitions)
    hoa.states;
  {
    Automata_exchange.initial_state = 0;
    state_count = List.length ordered_states;
    transitions = List.rev !transitions;
  }

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
  normalize_spot_monitor ~atom_names:request.atoms hoa
  |> Automata_exchange.make_response ~atoms:request.atoms
