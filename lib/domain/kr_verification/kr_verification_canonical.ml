(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *---------------------------------------------------------------------------*)

type stage =
  | Reference_product_built
  | Instrumented_ir_built

type t = {
  proof_cases : Kr_verification_cases.t;
  reference_product : Kr_verification_orchestration.reference_product;
  instrumented_nodes : Kr_verification_orchestration.instrumented_product_node list;
  obligations : Kr_verification_obligations.t list;
}

let ( let* ) = Result.bind

let build ?observe_fact_family ?pass_observer
    ?(observe_stage = fun _ -> ()) ?(body_effect_summaries = false)
    ~reachability_strategy ~proof_cases ~automata () =
  let input : Kr_verification_orchestration.reference_product_input =
    {
      proof_case_program = proof_cases;
      automata;
      reachability_strategy;
    }
  in
  let* reference_product =
    Kr_verification_orchestration.build_reference_product input
  in
  observe_stage Reference_product_built;
  let* instrumented_nodes =
    Kr_verification_orchestration.build_instrumented_ir ?observe_fact_family
      ?pass_observer ~body_effect_summaries reference_product
  in
  observe_stage Instrumented_ir_built;
  let partition_inputs =
    List.map
      Kr_verification_obligations.of_instrumented_product_node
      instrumented_nodes
  in
  let* obligations =
    Kr_verification_obligations.build_program ~proof_cases
      ~partition_inputs
  in
  Ok
    {
      proof_cases;
      reference_product;
      instrumented_nodes;
      obligations;
    }
