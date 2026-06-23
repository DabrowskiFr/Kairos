(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frederic Dabrowski
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

(** Stable naming conventions for product-step Why3 helpers. *)

val product_step_helper_name :
  index:int -> Why_runtime_view.runtime_product_transition_view -> string

val product_step_class_name : Why_runtime_view.runtime_step_class -> string

val product_step_group_helper_name :
  index:int -> Why_runtime_view.runtime_product_transition_view -> string

val product_source_label : Ir.product_state -> string
