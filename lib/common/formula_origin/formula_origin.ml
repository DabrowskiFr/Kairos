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

type t =
  | UserContract
  | Instrumentation
  | Invariant
  | GuaranteeAutomaton
  | GuaranteeViolation
  | GuaranteePropagation
  | AssumeAutomaton
  | ProgramGuard
  | StateStability
  | Internal
[@@deriving yojson]

let to_string = function
  | UserContract -> "user"
  | Instrumentation -> "instrumentation"
  | Invariant -> "invariant"
  | GuaranteeAutomaton -> "guarantee-automaton"
  | GuaranteeViolation -> "guarantee-violation"
  | GuaranteePropagation -> "guarantee-propagation"
  | AssumeAutomaton -> "assume-automaton"
  | ProgramGuard -> "program-guard"
  | StateStability -> "state-stability"
  | Internal -> "internal"

let of_string = function
  | "user" | "UserContract" -> Some UserContract
  | "instrumentation" | "monitor" | "Instrumentation" -> Some Instrumentation
  | "invariant" | "Invariant" | "coherency" | "Coherency" -> Some Invariant
  | "guarantee-automaton" | "GuaranteeAutomaton" -> Some GuaranteeAutomaton
  | "guarantee-violation" | "GuaranteeViolation" -> Some GuaranteeViolation
  | "guarantee-propagation" | "GuaranteePropagation" -> Some GuaranteePropagation
  | "assume-automaton" | "AssumeAutomaton" -> Some AssumeAutomaton
  | "program-guard" | "ProgramGuard" -> Some ProgramGuard
  | "state-stability" | "StateStability" -> Some StateStability
  | "internal" | "Internal" -> Some Internal
  | _ -> None
