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

    [Monolithic] is the literal identity. [Weak_until] is an
    equivalence-preserving endomorphism that builds smaller automata from
    groups of source guarantee occurrences. *)

type public_non_w_strategy =
  | Separate
  | Group_by_family

type strategy =
  | Monolithic
  | Weak_until of {
      public_non_w : public_non_w_strategy;
    }

val apply :
  strategy:strategy ->
  Proof_case_program.t ->
  (Proof_case_program.t, string) result
