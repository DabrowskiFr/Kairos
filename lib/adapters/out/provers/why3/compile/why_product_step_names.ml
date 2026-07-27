(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frederic Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

let product_step_helper_name ~(index : int)
    (step : Step_contract_projection.step_contract) =
  let step_class_suffix = function
    | Step_contract_projection.StepSafe -> "safe"
    | Step_contract_projection.StepBadGuarantee -> "bad_guarantee"
  in
  Printf.sprintf "step_%s_ps_%s_a%d_g%d_%s_%d"
    (String.lowercase_ascii step.transition_id)
    (String.lowercase_ascii step.product_src.prog_state)
    step.product_src.assume_state_index
    step.product_src.guarantee_state_index
    (step_class_suffix step.step_class)
    index

let product_step_group_helper_name ~(index : int)
    (step : Step_contract_projection.step_contract) =
  let step_class_suffix = function
    | Step_contract_projection.StepSafe -> "safe_group"
    | Step_contract_projection.StepBadGuarantee -> "bad_guarantee_group"
  in
  Printf.sprintf "step_%s_%s_%d"
    (String.lowercase_ascii step.transition_id)
    (step_class_suffix step.step_class)
    index
