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

let product_step_helper_name ~(index : int)
    (step : Why_runtime_view.runtime_product_transition_view) =
  let step_class_suffix = function
    | Why_runtime_view.StepSafe -> "safe"
    | Why_runtime_view.StepBadGuarantee -> "bad_guarantee"
  in
  Printf.sprintf "step_%s_ps_%s_a%d_g%d_%s_%d"
    (String.lowercase_ascii step.transition_id)
    (String.lowercase_ascii step.product_src.prog_state)
    step.product_src.assume_state_index
    step.product_src.guarantee_state_index
    (step_class_suffix step.step_class)
    index

let product_step_class_name = function
  | Why_runtime_view.StepSafe -> "safe"
  | Why_runtime_view.StepBadGuarantee -> "bad-guarantee"

let product_step_group_helper_name ~(index : int)
    (step : Why_runtime_view.runtime_product_transition_view) =
  let step_class_suffix = function
    | Why_runtime_view.StepSafe -> "safe_group"
    | Why_runtime_view.StepBadGuarantee -> "bad_guarantee_group"
  in
  Printf.sprintf "step_%s_%s_%d"
    (String.lowercase_ascii step.transition_id)
    (step_class_suffix step.step_class)
    index

let product_source_label (state : Ir.product_state) =
  Printf.sprintf "%s/a%d/g%d" state.prog_state state.assume_state_index
    state.guarantee_state_index
