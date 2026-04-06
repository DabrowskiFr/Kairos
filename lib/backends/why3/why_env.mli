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

(** Environment threaded through Why3 expression and contract compilation. *)

(* {1 Why3 Environment Preparation} *)

(* Precomputed data for emitting a node. *)
type env_info = Why_types.env_info

(* {2 Invariants}

   - [node] is the node used for emission. - [inputs] includes the implicit [vars] record binder
   (and inputs if any). - [env] records links/pre_k derived from [node] and collection passes. *)

(* Build environment data needed by the Why3 emission stages. *)
val prepare_runtime_view :
  prefix_fields:bool ->
  pre_k_map:(Ast.hexpr * Temporal_support.pre_k_info) list ->
  Why_runtime_view.t ->
  env_info

val prepare_ir_node :
  prefix_fields:bool ->
  Ir.node_ir ->
  env_info
