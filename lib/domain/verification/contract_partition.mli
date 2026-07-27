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

(** Scientific decomposition of verification contracts into reference nodes.

    The policy selects a domain-level grouping strategy. The transformation
    preserves an explicit relation between every generated reference node and
    its source node. *)

type policy = {
  group_public_non_w_guarantees : bool;
}

type provenance = {
  reference_node_name : Core_syntax.ident;
  source_node_name : Core_syntax.ident;
}

type partitioned_program = {
  program : Verification_model.program_model;
  provenance : provenance list;
}

val partition_program :
  policy:policy ->
  Verification_model.program_model ->
  (partitioned_program, string) result
