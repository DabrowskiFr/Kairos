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

(** Product helper planning facade.

    This module connects contract facts to the explicit helper plan. It does
    not emit Why3 declarations and does not record diagnostics. *)

type context = {
  env : Why_compile_expr.env;
  group_why3_product_steps : bool;
  why3_product_step_group_max_cost : int;
  simplify_why3_runtime_actions : bool;
}

val build :
  context ->
  Why_compile_contract_facts.product_helper_facts ->
  Why_contracts.step_contract_info list ->
  Why_compile_product_groups.helper_plan_item list
