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

(* {1 Contract Assembly} Translate node contracts (assumes/guarantees and transition
   requires/ensures) into Why3 pre/post terms with labels for UI/VC tracing. *)

(* {1 Contract Assembly} *)

type contract_info = Why_types.contract_info
(* Pre/post conditions with label groups for UI diagnostics. *)

val set_pure_translation : bool -> unit
(* Enable/disable pure translation mode (no extra contract generation). *)

(* {2 Invariants}

   - [build_contracts] expects [env_info] produced by [prepare_node]. *)

val build_contracts :
  nodes:Ast.node list ->
  ?kernel_ir:Product_kernel_ir.node_ir ->
  Why_env.env_info ->
  contract_info
(* Build full contract terms (pre/post) and their labels. *)

val build_contracts_runtime_view :
  nodes:Ast.node list ->
  ?kernel_ir:Product_kernel_ir.node_ir ->
  Why_env.env_info ->
  Why_runtime_view.t ->
  contract_info
(* Same as [build_contracts], but driven explicitly by the abstract Why runtime view. *)
