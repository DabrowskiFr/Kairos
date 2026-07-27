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

open Core_syntax
open Core_syntax_builders

module Automata_exchange = Kairos_automata_contract.Automata_exchange

let ( let* ) = Result.bind

let build_prepared_formula
    ~(build_automaton :
       Automata_exchange.request -> Automata_exchange.response)
    (prepared : Automata_preparation.prepared_formula) :
    Automaton_types.automaton =
  Automata_exchange_adapter.request_of_core ~atom_map:prepared.atoms
    prepared.formula
  |> build_automaton
  |> Automata_exchange_adapter.automaton_of_response
       ~atom_map:prepared.atoms

let trivial_assumption_automaton : Automaton_types.automaton =
  {
    states = [ LTrue ];
    transitions = [ (0, mk_hbool true, 0) ];
  }

let build_prepared_node
    ~(build_automaton :
       Automata_exchange.request -> Automata_exchange.response)
    (prepared : Automata_preparation.prepared_node) :
    Automaton_types.automata_spec =
  let guarantee_automaton =
    build_prepared_formula ~build_automaton prepared.guarantee
  in
  let assume_automaton =
    match prepared.assumption with
    | None -> trivial_assumption_automaton
    | Some assumption ->
        build_prepared_formula ~build_automaton assumption
  in
  {
    Automaton_types.guarantee_automaton;
    assume_automaton;
  }

let run (program : Verification_model.program_model)
    ~(build_automaton :
       Automata_exchange.request -> Automata_exchange.response) :
    ( (ident * Automaton_types.automata_spec) list
      * Flow_info.automata_info,
      string )
    result =
  let* prepared_nodes =
    Automata_preparation.prepare_program program
  in
  let rec build_nodes automata_rev state_count edge_count = function
    | [] ->
        Ok
          ( List.rev automata_rev,
            {
              Flow_info.residual_state_count = state_count;
              residual_edge_count = edge_count;
              warnings = [];
            } )
    | (prepared : Automata_preparation.prepared_node) :: rest ->
        let automata =
          build_prepared_node ~build_automaton prepared
        in
        let guarantee = automata.guarantee_automaton in
        build_nodes
          ((prepared.node_name, automata) :: automata_rev)
          (state_count + List.length guarantee.states)
          (edge_count + List.length guarantee.transitions)
          rest
  in
  build_nodes [] 0 0 prepared_nodes
