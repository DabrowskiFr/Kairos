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
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *---------------------------------------------------------------------------*)

(** Grouping policy for product-step Why3 helpers. *)

type entry = Why_compile_product_group_boundary.entry

type individual_reason =
  | Grouping_disabled
  | Empty_group
  | Singleton_group
  | Non_safe_step
  | Has_local_cuts
  | Split_singleton

type decision =
  | Groupable
  | Individual of individual_reason

val individual_reason_name : individual_reason -> string

val decide_group : group_why3_product_steps:bool -> entry list -> decision
