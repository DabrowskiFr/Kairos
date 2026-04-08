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

type stage_id = Parsed | Automaton | Contracts | Instrumentation | Why | Prove

let ast_stages = [ Parsed; Automaton; Instrumentation; Contracts ]
let all = ast_stages @ [ Why; Prove ]

let to_string = function
  | Parsed -> "parsed"
  | Automaton -> "automaton"
  | Contracts -> "contracts"
  | Instrumentation -> "ir_construction"
  | Why -> "why"
  | Prove -> "prove"

let description = function
  | Parsed -> "after parsing"
  | Automaton -> "after automata generation"
  | Instrumentation -> "after IR construction"
  | Contracts -> "after user contract initialization"
  | Why -> "after Why3 generation"
  | Prove -> "after Why3 proof"

let of_string = function
  | "parsed" -> Ok Parsed
  | "automaton" -> Ok Automaton
  | "contracts" -> Ok Contracts
  | "ir_construction" | "instrumentation" | "monitor" -> Ok Instrumentation
  | other ->
      Error
        ("Unknown stage for --dump-ast. Use: "
        ^ String.concat "|" (List.map to_string ast_stages)
        ^ " (got " ^ other ^ ")")
