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

type atom_map = (ltl_atom * ident) list

let atom_name ~atom_map atom =
  match List.find_opt (fun (candidate, _) -> candidate = atom) atom_map with
  | Some (_, name) -> name
  | None -> invalid_arg "automata contract conversion encountered an unmapped temporal atom"

let rec ltl_of_core ~atom_map = function
  | LTrue -> Automata_exchange.True
  | LFalse -> False
  | LAtom atom -> Atom (atom_name ~atom_map atom)
  | LNot formula -> Not (ltl_of_core ~atom_map formula)
  | LAnd (left, right) -> And (ltl_of_core ~atom_map left, ltl_of_core ~atom_map right)
  | LOr (left, right) -> Or (ltl_of_core ~atom_map left, ltl_of_core ~atom_map right)
  | LImp (left, right) -> Implies (ltl_of_core ~atom_map left, ltl_of_core ~atom_map right)
  | LX formula -> Next (ltl_of_core ~atom_map formula)
  | LG formula -> Always (ltl_of_core ~atom_map formula)
  | LW (left, right) -> Weak_until (ltl_of_core ~atom_map left, ltl_of_core ~atom_map right)

let request_of_core ~atom_map formula =
  let atoms = List.map snd atom_map in
  Automata_exchange.make_request ~atoms (ltl_of_core ~atom_map formula)

let atom_of_name ~atom_map name =
  match List.find_opt (fun (_, candidate) -> String.equal candidate name) atom_map with
  | Some (atom, _) -> atom
  | None -> invalid_arg (Printf.sprintf "automata response references unknown atom %S" name)

let rec hexpr_of_guard ~atom_map = function
  | Automata_exchange.Guard_true -> mk_hbool true
  | Guard_false -> mk_hbool false
  | Guard_atom name ->
      let left, relation, right = atom_of_name ~atom_map name in
      mk_hexpr (HCmp (relation, left, right))
  | Guard_not guard -> mk_hexpr (HUn (Not, hexpr_of_guard ~atom_map guard))
  | Guard_and (left, right) ->
      mk_hexpr (HBin (And, hexpr_of_guard ~atom_map left, hexpr_of_guard ~atom_map right))
  | Guard_or (left, right) ->
      mk_hexpr (HBin (Or, hexpr_of_guard ~atom_map left, hexpr_of_guard ~atom_map right))

let automaton_of_response ~atom_map (response : Automata_exchange.response) :
    Automaton_types.automaton =
  (match Automata_exchange.validate_response response with
  | Ok () -> ()
  | Error message -> invalid_arg message);
  let expected_atoms = List.map snd atom_map in
  if response.atoms <> expected_atoms then
    invalid_arg "automata response atom domain differs from its request";
  let states =
    List.map
      (function Automata_exchange.Accepting -> LTrue | Rejecting -> LFalse)
      response.automaton.states
  in
  let transitions =
    List.map
      (fun (edge : Automata_exchange.edge) ->
        (edge.source, hexpr_of_guard ~atom_map edge.guard, edge.target))
      response.automaton.transitions
  in
  { Automaton_types.states; transitions }
