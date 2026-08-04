(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frederic Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

module Kr_verification_step_contract =
  Kr_verification.Kr_verification_step_contract

let product_step_helper_name ~(node_name : Kr_domain_core_syntax.ident)
    ~(index : int)
    (step : Kr_verification_step_contract.step_contract) =
  let product_source =
    Kr_verification_step_contract.product_source step
  in
  Printf.sprintf "__kairos_proof_unit_%s_%s_ps_%s_a%d_g%d_%d"
    (String.lowercase_ascii node_name)
    (String.lowercase_ascii step.transition_id)
    (String.lowercase_ascii product_source.prog_state)
    product_source.assume_state_index
    product_source.guarantee_state_index
    index

let product_step_group_helper_name ~(node_name : Kr_domain_core_syntax.ident)
    ~(index : int)
    (step : Kr_verification_step_contract.step_contract) =
  Printf.sprintf "__kairos_proof_unit_%s_%s_group_%d"
    (String.lowercase_ascii node_name)
    (String.lowercase_ascii step.transition_id)
    index
