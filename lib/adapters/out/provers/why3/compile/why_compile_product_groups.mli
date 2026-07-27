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

(** Product-step helper planning.

    This module decides which product steps are emitted individually and which
    ones are bundled into grouped helpers. It does not emit Why3 declarations. *)

module Group_partition : sig
  type entry = Why_compile_product_group_terms.entry

  val partition : entry list -> entry list list
end

module Group_policy : sig
  type entry = Why_compile_product_group_terms.entry

  type decision = Groupable | Individual

  val decide_group :
    group_why3_product_steps:bool -> entry list -> decision
end

type individual_plan = {
  index : int;
  contract : Step_contract_projection.step_contract;
}

type grouped_plan = {
  index : int;
  contract : Step_contract_projection.step_contract;
  group_size : int;
  formulas : Core_syntax.history_free Ir.summary_formula list;
  grouped_terms : Why_compile_product_group_terms.t;
}

type helper_plan_item =
  | Individual of individual_plan
  | Grouped of grouped_plan

val build :
  env:Why_compile_expr.env ->
  formula_sharing:Why_compile_formula_sharing.t ->
  group_why3_product_steps:bool ->
  Step_contract_projection.step_contract list ->
  helper_plan_item list
