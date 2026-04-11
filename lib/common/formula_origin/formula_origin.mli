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

(** Origin tags attached to contract formulas.

    These tags classify formulas for:
    {ul
    {- diagnostics;}
    {- rendering;}
    {- obligation labeling.}} *)
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

(** Stable textual encoding used in artifacts and diagnostics. *)
val to_string : t -> string

(** Partial inverse of {!to_string}. *)
val of_string : string -> t option
