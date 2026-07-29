(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frederic Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

module Step_contract_projection =
  Kairos_verification_obligations.Step_contract_projection

let product_step_helper_name ~(index : int)
    (step : Step_contract_projection.step_contract) =
  Printf.sprintf "step_%s_ps_%s_a%d_g%d_%d"
    (String.lowercase_ascii step.transition_id)
    (String.lowercase_ascii step.product_src.prog_state)
    step.product_src.assume_state_index
    step.product_src.guarantee_state_index
    index

let product_step_group_helper_name ~(index : int)
    (step : Step_contract_projection.step_contract) =
  Printf.sprintf "step_%s_group_%d"
    (String.lowercase_ascii step.transition_id)
    index
