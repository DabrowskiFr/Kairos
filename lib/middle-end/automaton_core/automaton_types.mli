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

(** {1 Residual Automaton Types} *)

type residual_state = Ast.fo_ltl
(** Residual automaton state as an LTL formula. *)
type residual_transition = int * (string * bool) list * int
(** Residual transition (src, valuation, dst). *)
type grouped_transition = int * (string * bool) list list * int
(** Residual transition grouped by destination (src, valuations, dst). *)
type bdd_guard = int
(** BDD guard identifier. *)
type bdd_transition = int * bdd_guard * int
(** Residual transition grouped with a BDD guard (src, guard, dst). *)
type guard = (string * bool option) list list
(** DNF guard as a list of implicants (each implicant lists literals). *)
type guarded_transition = int * guard * int
(** Residual transition grouped with a DNF guard (src, guard, dst). *)
