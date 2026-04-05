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

(** DOT renderers for the annotated, verified, and kernel IR layers. *)

(*---------------------------------------------------------------------------
 * Kairos — DOT graph renderer for the three IR layers.
 *
 * Produces Graphviz DOT representations of IR nodes for visualization.
 *---------------------------------------------------------------------------*)

val dot_of_annotated_node : Ir.annotated_node -> string
val dot_of_verified_node : Ir.verified_node -> string
val dot_of_kernel_node_ir : Proof_kernel_types.node_ir -> string
