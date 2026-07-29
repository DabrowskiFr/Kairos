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
  proof_cases : Proof_case_program.t;
  reference_product : Orchestration.reference_product;
  instrumented_nodes : Orchestration.instrumented_product_node list;
  obligations : Verification_obligations.t list;
}

let ( let* ) = Result.bind

let build ?observe_fact_family ?pass_observer
    ?(observe_stage = fun _ -> ()) ~reachability_strategy
    ~proof_cases ~automata () =
  let input : Orchestration.reference_product_input =
    {
      proof_case_program = proof_cases;
      automata;
      reachability_strategy;
    }
  in
  let* reference_product =
    Orchestration.build_reference_product input
  in
  observe_stage Reference_product_built;
  let* instrumented_nodes =
    Orchestration.build_instrumented_ir ?observe_fact_family
      ?pass_observer reference_product
  in
  observe_stage Instrumented_ir_built;
  let partition_inputs =
    List.map
      Verification_obligations.of_instrumented_product_node
      instrumented_nodes
  in
  let* obligations =
    Verification_obligations.build_program ~proof_cases
      ~partition_inputs
  in
  Ok
    {
      proof_cases;
      reference_product;
      instrumented_nodes;
      obligations;
    }
