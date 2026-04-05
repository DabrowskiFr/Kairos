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

(** Pass 3: compute and attach the node-level pre_k map in the IR node context. *)

val compute_pre_k_map : Ir.node_ir -> (Ast.hexpr * Temporal_support.pre_k_info) list
val build_raw_node : program_transitions:Ir.transition list -> Ir.node_ir -> Ir_proof_views.raw_node

val apply_node : Ir.node_ir -> Ir.node_ir
val apply_program : Ir.node_ir list -> Ir.node_ir list
