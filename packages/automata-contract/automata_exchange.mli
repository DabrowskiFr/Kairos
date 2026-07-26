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

(** Versioned, tool-neutral contract for safety-automata producers.

    Atomic propositions are opaque names. Neither requests nor responses contain source-language,
    verification-kernel, or backend-specific values. *)

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
type state_kind = Accepting | Rejecting [@@deriving yojson]
type edge = { source : int; guard : guard; target : int } [@@deriving yojson]

type automaton = { initial_state : int; states : state_kind list; transitions : edge list }
[@@deriving yojson]

type response = { protocol_version : int; atoms : atom list; automaton : automaton }
[@@deriving yojson]

val current_protocol_version : int
val make_request : atoms:atom list -> ltl -> request
val make_response : atoms:atom list -> automaton -> response
val validate_request : request -> (unit, string) result
val validate_response : response -> (unit, string) result
val atoms_of_ltl : ltl -> atom list
val atoms_of_guard : guard -> atom list
