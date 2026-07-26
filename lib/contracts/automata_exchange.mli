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

(** Versioned, tool-neutral exchange contract for safety-automata producers.

    The types in this module are deliberately independent from
    [Automaton_types]. An external producer can consume and emit this contract
    without depending on the verification kernel. Runtime orchestration owns
    the conversion to the kernel representation. *)

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

val make_request :
  atom_map:(Core_syntax.ltl_atom * Core_syntax.ident) list ->
  Core_syntax.ltl ->
  request

val make_response : automaton -> response

val validate_request : request -> (unit, string) result
val validate_response : response -> (unit, string) result
