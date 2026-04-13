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

(** Helpers over [Ir.summary_formula]. *)
open Core_syntax
(** [make] service entrypoint. *)

val make :
  ?loc:Loc.loc ->
  Core_syntax.hexpr ->
  Ir.summary_formula

(** [values] service entrypoint. *)

val values : Ir.summary_formula list -> Core_syntax.hexpr list

(** [temporal_bindings_of_layout] service entrypoint. *)

val temporal_bindings_of_layout :
  Ir.temporal_layout ->
  Pre_k_lowering.temporal_binding list

(** [temporal_bindings_of_node] service entrypoint. *)

val temporal_bindings_of_node :
  Ir.node_ir ->
  Pre_k_lowering.temporal_binding list
