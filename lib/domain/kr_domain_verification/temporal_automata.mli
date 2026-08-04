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

(** Product-automata analysis output.

    This interface describes the per-node product exploration data reused by
    IR construction, proof planning and artifact renderers. *)

open Core_syntax
(** Result of the explicit product exploration for one normalized node.

    The node data keeps both the reachable product graph itself and the metadata
    needed later by renderers and proof-planning passes. *)

(** Full exploration result together with auxiliary automata metadata. *)
type node_data = {
  (** Reachable product states and explicit product steps. *)
  exploration : Product_types.exploration;
  (** Deterministic partial guarantee monitor, unchanged. *)
  guarantee_monitor : Automaton_types.deterministic_partial_monitor;
  (** Deterministic partial assumption monitor, unchanged. *)
  assume_monitor : Automaton_types.deterministic_partial_monitor;
}
