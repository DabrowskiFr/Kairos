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

(** Pass 5: history elimination over the Kairos IR. *)

(*---------------------------------------------------------------------------
 * Kairos — Pass 5: History elimination.
 *
 * Keeps proof views aligned with summary IR while preserving temporal
 * expressions [HPreK] as logical atoms.
 *---------------------------------------------------------------------------*)

(** Build the verified proof view from the annotated one. *)

val eliminate : Ir_proof_views.annotated_node -> Ir_proof_views.verified_node
val apply_node : Ir.node_ir -> Ir.node_ir
val apply_program : Ir.node_ir list -> Ir.node_ir list
