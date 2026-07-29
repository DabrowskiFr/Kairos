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

(** Optional decomposition of core-owned verification cases.

    [Monolithic] is the literal identity. [Separate_guarantees] creates one case
    per source guarantee occurrence. [Split_multiple_weak_until] creates
    independent proof cases only when at least two source guarantee occurrences
    contain weak-until. Each such occurrence gets one case; all remaining
    guarantees share one case. *)

type strategy =
  | Monolithic
  | Separate_guarantees
  | Split_multiple_weak_until

val apply :
  strategy:strategy ->
  Proof_case_program.t ->
  (Proof_case_program.t, string) result
