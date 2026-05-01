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

 (** Semantic automata data shared by the middle-end.

    This module describes:
    {ul
    {- semantic transition guards;}
    {- normalized automata;}
    {- per-node automata generation results.}} *)

(** Boolean guard carried by an automaton transition.

    Guards are stored as first-order formulas over history expressions. *)
type guard = Core_syntax.hexpr

(** Transition represented as [(src_index, guard, dst_index)]. *)
type transition = int * guard * int

(** Safety automaton. *)
type automaton = {
  states : Core_syntax.ltl list;
  transitions : transition list;
}

(** Per-node automata generation result.

    A node carries:
    {ul
    {- one guarantee automaton;}
    {- one assumption automaton .}} *)
type automata_spec = {
  guarantee_automaton : automaton;
  assume_automaton : automaton;
}
