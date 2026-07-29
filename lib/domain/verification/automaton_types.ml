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

(** Typed monitor boundary used by the reference product construction. *)

type guard = Core_syntax.historical Core_syntax.hexpr
type transition = int * guard * int

type deterministic_partial_monitor = {
  initial_state : int;
  state_count : int;
  transitions : transition list;
}

type automata_spec = {
  guarantee_monitor : deterministic_partial_monitor;
  assume_monitor : deterministic_partial_monitor;
}
