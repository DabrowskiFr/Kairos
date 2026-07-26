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

(** Low-level bridge from the versioned automata request to Spot.

    This module is responsible for invoking the external safety-automaton
    backend and normalizing its result into the tool-neutral exchange
    representation. It does not depend on the verification kernel. *)
(** [build] service entrypoint. *)

val build :
  Kairos_tool_contracts.Automata_exchange.request ->
  Kairos_tool_contracts.Automata_exchange.response
(** [build request] constructs the safety automaton requested by Kairos and
    returns a versioned response. *)
