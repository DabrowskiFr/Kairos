(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
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

module Canonical_verification =
  Kr_verification.Kr_verification_canonical

module Kr_verification_proof_ir =
  Kr_verification.Kr_verification_proof_ir

module Kr_verification_case_strategy =
  Kr_verification.Kr_verification_case_strategy

module Kr_verification_plan =
  Kr_verification.Kr_verification_plan

let ( let* ) = Result.bind

let ir_size_metrics :
    type phase.
    phase Kr_verification_ir.node_ir list ->
    Runtime_metrics.ir_size_metrics =
 fun nodes ->
  let summary_count = ref 0 in
  let product_case_count = ref 0 in
  let propagation_requires_count = ref 0 in
  let requires_count = ref 0 in
  let ensures_count = ref 0 in
  let elaboration_checks_count = ref 0 in
  let formula_occurrence_count = ref 0 in
  let formulas = ref [] in
  let add_formula f =
    incr formula_occurrence_count;
    formulas := f :: !formulas
  in
  let add_summary_formula (f : phase Kr_verification_ir.summary_formula) =
    add_formula f.logic
  in
  List.iter
    (fun (node : phase Kr_verification_ir.node_ir) ->
      List.iter
        (fun (summary : phase Kr_verification_ir.product_step_summary) ->
          incr summary_count;
          propagation_requires_count :=
            !propagation_requires_count
            + List.length summary.propagation_requires;
          requires_count := !requires_count + List.length summary.requires;
          ensures_count := !ensures_count + List.length summary.ensures;
          elaboration_checks_count :=
            !elaboration_checks_count
            + List.length summary.elaboration_checks;
          product_case_count :=
            !product_case_count + List.length summary.product_cases;
          List.iter add_summary_formula summary.propagation_requires;
          List.iter add_summary_formula summary.requires;
          List.iter add_summary_formula summary.ensures;
          List.iter add_summary_formula summary.elaboration_checks;
          List.iter
            (fun (case : phase Kr_verification_ir.product_case) ->
              add_summary_formula case.guarantee_guard)
            summary.product_cases)
        node.summaries)
    nodes;
  {
    node_count = List.length nodes;
    summary_count = !summary_count;
    product_case_count = !product_case_count;
    propagation_requires_count = !propagation_requires_count;
    requires_count = !requires_count;
    ensures_count = !ensures_count;
    elaboration_checks_count = !elaboration_checks_count;
    formula_occurrence_count = !formula_occurrence_count;
    unique_formula_count = List.length (List.sort_uniq Stdlib.compare !formulas);
  }

let ir_pass_name = function
  | Kr_verification_orchestration.Pre_pass -> "pre"
  | Kr_verification_orchestration.Post_pass -> "post"
  | Kr_verification_orchestration.Temporal_lower_pass -> "temporal_lower"

let record_ir_fact_family (family : Kr_verification_fact_metrics.snapshot) =
  Runtime_metrics.record_ir_fact_family
    {
      pass_name = family.pass_name;
      family_name = family.family_name;
      candidate_count = family.candidate_count;
      inserted_count = family.inserted_count;
      unique_candidate_count = family.unique_candidate_count;
      unique_inserted_count = family.unique_inserted_count;
    }

type prepared_program = {
  parse_info : Kr_engine.Kr_engine_flow_info.parse_info;
  proof_case_program : Kr_verification_cases.t;
}

type build_result = {
  verification : Canonical_verification.t;
  proof_plans : Kr_verification_proof_ir.t list;
  infos : Kr_engine.Kr_engine_flow_info.pipeline_info;
}

let prepare_program
    ~(proof_optimizations : Kr_engine.Kr_engine_pipeline_config.proof_optimizations)
    ~(parse_info : Kr_engine.Kr_engine_flow_info.parse_info)
    ~(verification_model : Kr_domain_core_model.program_model) :
    (prepared_program, Kr_engine.Kr_engine_pipeline_error.t) result =
  try
    let p_model = verification_model in
    let t_decomposition = Unix.gettimeofday () in
    let decomposition_result =
      p_model
      |> Kr_verification_cases.minimal
      |> Kr_verification_case_strategy.apply
        ~strategy:
          proof_optimizations.verification
            .proof_case_decomposition_strategy
    in
    Runtime_metrics.record_proof_case_decomposition
      ~elapsed_s:(Unix.gettimeofday () -. t_decomposition);
    let* proof_case_program =
      decomposition_result
      |> Result.map_error (fun msg -> Kr_engine.Kr_engine_pipeline_error.Flow_error msg)
    in
    Ok
      {
        parse_info;
        proof_case_program;
      }
  with exn -> Error (Kr_engine.Kr_engine_pipeline_error.Flow_error (Printexc.to_string exn))

let build_from_supplied_automata
    ~(collect_instrumentation_info : bool)
    ~(collect_ir_metrics : bool)
    ~(proof_optimizations : Kr_engine.Kr_engine_pipeline_config.proof_optimizations)
    ~(prepared : prepared_program)
    ~(automata :
       (Kr_domain_core_syntax.ident * Kr_verification_automata_types.automata_spec) list)
    ~(automata_info : Kr_engine.Kr_engine_flow_info.automata_info) :
    (build_result, Kr_engine.Kr_engine_pipeline_error.t) result =
  try
    let parse_info = prepared.parse_info in
    let proof_case_program = prepared.proof_case_program in
    let stage_started_at = ref (Unix.gettimeofday ()) in
    let proof_planning_started_at = ref 0.0 in
    let pass_started_at = ref 0.0 in
    let pass_before = ref None in
    let begin_pass nodes =
      pass_before :=
        (if collect_ir_metrics then
           Some (ir_size_metrics nodes)
         else None);
      pass_started_at := Unix.gettimeofday ()
    in
    let finish_pass pass after =
      let elapsed_s =
        Unix.gettimeofday () -. !pass_started_at
      in
      (match pass with
      | Kr_verification_orchestration.Pre_pass -> Runtime_metrics.record_pre ~elapsed_s
      | Kr_verification_orchestration.Post_pass -> Runtime_metrics.record_post ~elapsed_s
      | Kr_verification_orchestration.Temporal_lower_pass ->
          Runtime_metrics.record_temporal_lower ~elapsed_s);
      (match (!pass_before, after) with
      | Some before, Some after_ ->
          Runtime_metrics.record_ir_pass
            {
              pass_name = ir_pass_name pass;
              before;
              after_;
            }
      | None, None -> ()
      | Some _, None | None, Some _ ->
          invalid_arg
            "Pipeline_build: inconsistent IR metrics observation");
      pass_before := None
    in
    let finish_historical pass nodes =
      finish_pass pass
        (if collect_ir_metrics then
           Some (ir_size_metrics nodes)
         else None)
    in
    let finish_lowering pass nodes =
      finish_pass pass
        (if collect_ir_metrics then
           Some (ir_size_metrics nodes)
         else None)
    in
    let pass_observer : Kr_verification_orchestration.pass_observer =
      {
        before_historical = (fun _ nodes -> begin_pass nodes);
        after_historical = finish_historical;
        before_lowering = (fun _ nodes -> begin_pass nodes);
        after_lowering = finish_lowering;
      }
    in
    let observe_stage = function
      | Canonical_verification.Reference_product_built ->
          let now = Unix.gettimeofday () in
          Runtime_metrics.record_product
            ~elapsed_s:(now -. !stage_started_at);
          stage_started_at := now
      | Canonical_verification.Instrumented_ir_built ->
          let now = Unix.gettimeofday () in
          Runtime_metrics.record_canonical
            ~elapsed_s:(now -. !stage_started_at);
          proof_planning_started_at := now
    in
    let* canonical =
      Canonical_verification.build
        ?observe_fact_family:
          (if collect_ir_metrics then
             Some record_ir_fact_family
           else None)
        ~pass_observer ~observe_stage
        ~reachability_strategy:
          proof_optimizations.verification.reachability_strategy
        ~proof_cases:proof_case_program ~automata
        ()
      |> Result.map_error (fun message ->
             Kr_engine.Kr_engine_pipeline_error.Flow_error message)
    in
    let reference_product = canonical.reference_product in
    let product_nodes = reference_product.nodes in
    let instrumented_product_nodes =
      canonical.instrumented_nodes
    in
    let p_instrumentation =
      List.map
        (fun
          (node : Kr_verification_orchestration.instrumented_product_node)
        ->
          node.ir)
        instrumented_product_nodes
    in
    let ir_program : Kr_verification_ir.program_ir =
      { nodes = p_instrumentation }
    in
    let individual_obligations = canonical.obligations in
        let minimal_proof_plans =
          Kr_verification_proof_ir.minimal_program
            individual_obligations
        in
        let* proof_plans =
          Kr_verification_plan.apply_program
            ~strategy:
              proof_optimizations.verification.proof_plan_strategy
            minimal_proof_plans
          |> Result.map_error (fun msg ->
                 Kr_engine.Kr_engine_pipeline_error.Flow_error msg)
        in
        Runtime_metrics.record_proof_planning
          ~elapsed_s:
            (Unix.gettimeofday ()
            -. !proof_planning_started_at);
        let summaries_info : Kr_engine.Kr_engine_flow_info.summaries_info = { warnings = [] }
        in
        let instrumentation_info =
          if collect_instrumentation_info then
            let t_info = Unix.gettimeofday () in
            let result =
              Instrumentation_info_builder.instrumentation_info_of_ir
                ~product_nodes ir_program
            in
            Runtime_metrics.record_instrumentation_info
              ~elapsed_s:(Unix.gettimeofday () -. t_info);
            result |> Result.map Option.some
          else Ok None
        in
        match instrumentation_info with
        | Error msg -> Error (Kr_engine.Kr_engine_pipeline_error.Flow_error msg)
        | Ok instrumentation_info ->
        let infos : Kr_engine.Kr_engine_flow_info.pipeline_info =
          {
            parse = Some parse_info;
            automata_generation = Some automata_info;
            summaries = Some summaries_info;
            instrumentation = instrumentation_info;
          }
        in
        Ok { verification = canonical; proof_plans; infos }
  with exn -> Error (Kr_engine.Kr_engine_pipeline_error.Flow_error (Printexc.to_string exn))
