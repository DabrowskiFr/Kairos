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

(** Semantic automata supplied to the reference product construction.

    Automata are treated as explicit inputs to the proof-relevant pipeline. The
    construction of those automata, for example by Spot, is outside this module
    and outside the core correction claim. *)

(** Boolean guard carried by an automaton transition. *)
type guard = Core_syntax.hexpr

(** Transition represented as [(src_index, guard, dst_index)]. *)
type transition = int * guard * int

(** Safety automaton consumed by product exploration. *)
type automaton = {
  states : Core_syntax.ltl list;
  transitions : transition list;
}

(** Per-node assumption/guarantee automata pair. *)
type automata_spec = {
  guarantee_automaton : automaton;
  assume_automaton : automaton;
}
