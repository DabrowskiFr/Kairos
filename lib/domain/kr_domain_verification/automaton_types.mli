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

(** Typed monitor boundary used by the reference product construction. *)

(** Boolean guard carried by an automaton transition. *)
type guard = Core_syntax.historical Core_syntax.hexpr

(** Transition represented as [(src_index, guard, dst_index)]. *)
type transition = int * guard * int

(** Deterministic partial monitor supplied by the producer.

    For any source state, guards leading to distinct successors are mutually
    exclusive. They need not be complete: a valuation satisfying no outgoing
    guard blocks the monitor. This is a producer invariant; the verification
    core deliberately performs no determinization or propositional search. *)
type deterministic_partial_monitor = {
  initial_state : int;
  state_count : int;
  transitions : transition list;
}

(** Per-node assumption/guarantee monitor pair. *)
type automata_spec = {
  guarantee_monitor : deterministic_partial_monitor;
  assume_monitor : deterministic_partial_monitor;
}
