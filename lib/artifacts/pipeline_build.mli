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

(** Imported AST construction and IR/object extraction for the main pipeline. *)

type ir_nodes = {
  raw_ir_nodes : Ir_proof_views.raw_node list;
  annotated_ir_nodes : Ir_proof_views.annotated_node list;
  verified_ir_nodes : Ir_proof_views.verified_node list;
  kernel_ir_nodes : Proof_kernel_types.node_ir list;
}

val build_ast_with_info :
  input_file:string ->
  unit ->
  (Pipeline_types.ast_stages * Pipeline_types.stage_infos, Pipeline_types.error) result

val dump_ir_nodes : input_file:string -> (ir_nodes, Pipeline_types.error) result

val compile_object :
  input_file:string -> (Kairos_object.t, Pipeline_types.error) result
