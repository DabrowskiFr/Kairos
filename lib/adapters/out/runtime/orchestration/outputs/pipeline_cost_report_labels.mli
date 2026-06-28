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

(** Stable textual labels used by diagnostic cost reports. *)

val clause_family_string :
  Obligation_family_projection.clause_family -> string

val phase_string : Kernel_clause_projection.time_tag -> string
val step_kind_string : Proof_kernel_types.product_step_kind -> string
val string_of_product_state : Proof_kernel_types.product_state_ir -> string
val origin_for_node : string -> string -> string
