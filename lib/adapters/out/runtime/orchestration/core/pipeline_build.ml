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

module Verification_obligations =
  Kairos_verification_obligations.Verification_obligations

module Verification_proof_ir =
  Kairos_verification_obligations.Verification_proof_ir

module Contract_partition =
  Kairos_verification_optimization.Contract_partition

module Formula_interning =
  Kairos_verification_optimization.Formula_interning

module Proof_plan =
  Kairos_verification_optimization.Proof_plan

let ( let* ) = Result.bind

let rec stmt_contains_call (s : Core_syntax.stmt) : bool =
  match s.stmt with
  | SCall _ -> true
  | SIf (_, then_branch, else_branch) ->
      List.exists stmt_contains_call then_branch || List.exists stmt_contains_call else_branch
  | SWhile (_, _, _, body) -> List.exists stmt_contains_call body
  | SMatch (_, branches, default_branch) ->
      List.exists
        (fun (_ctor, body) -> List.exists stmt_contains_call body)
        branches
      || List.exists stmt_contains_call default_branch
  | SAssign _ | SAssert _ | SSkip -> false

let transition_contains_call (t : Verification_model.program_step) : bool =
  List.exists stmt_contains_call t.body_stmts

let node_uses_calls (n : Verification_model.node_model) : bool =
  List.exists transition_contains_call n.steps

let reject_calls (program : Verification_model.program_model) : (unit, Pipeline_error.t) result =
  match List.find_opt node_uses_calls program with
  | None -> Ok ()
  | Some n ->
      Error
        (Pipeline_error.Flow_error
           (Printf.sprintf
              "Calls are not supported in this Kairos version (node '%s')."
              n.node_name))

let ir_size_metrics :
    type phase.
    phase Ir.node_ir list ->
    Runtime_metrics.ir_size_metrics =
 fun nodes ->
  let summary_count = ref 0 in
  let safe_case_count = ref 0 in
  let unsafe_case_count = ref 0 in
  let propagation_requires_count = ref 0 in
  let requires_count = ref 0 in
  let ensures_count = ref 0 in
  let elaboration_checks_count = ref 0 in
  let init_invariant_goal_count = ref 0 in
  let formula_occurrence_count = ref 0 in
  let formulas = ref [] in
  let add_formula f =
    incr formula_occurrence_count;
    formulas := f :: !formulas
  in
  let add_summary_formula (f : phase Ir.summary_formula) =
    add_formula f.logic
  in
  List.iter
    (fun (node : phase Ir.node_ir) ->
      init_invariant_goal_count :=
        !init_invariant_goal_count + List.length node.init_invariant_goals;
      List.iter add_summary_formula node.init_invariant_goals;
      List.iter
        (fun (summary : phase Ir.product_step_summary) ->
          incr summary_count;
          propagation_requires_count :=
            !propagation_requires_count
            + List.length summary.propagation_requires;
          requires_count := !requires_count + List.length summary.requires;
          ensures_count := !ensures_count + List.length summary.ensures;
          elaboration_checks_count :=
            !elaboration_checks_count
            + List.length summary.elaboration_checks;
          safe_case_count := !safe_case_count + List.length summary.safe_cases;
          unsafe_case_count := !unsafe_case_count + List.length summary.unsafe_cases;
          List.iter add_summary_formula summary.propagation_requires;
          List.iter add_summary_formula summary.requires;
          List.iter add_summary_formula summary.ensures;
          List.iter add_summary_formula summary.elaboration_checks;
          List.iter
            (fun (case : phase Ir.safe_product_case) ->
              add_summary_formula case.admissible_guard)
            summary.safe_cases;
          List.iter
            (fun (case : phase Ir.unsafe_product_case) ->
              add_summary_formula case.excluded_guard)
            summary.unsafe_cases)
        node.summaries)
    nodes;
  {
    node_count = List.length nodes;
    summary_count = !summary_count;
    safe_case_count = !safe_case_count;
    unsafe_case_count = !unsafe_case_count;
    propagation_requires_count = !propagation_requires_count;
    requires_count = !requires_count;
    ensures_count = !ensures_count;
    elaboration_checks_count = !elaboration_checks_count;
    init_invariant_goal_count = !init_invariant_goal_count;
    formula_occurrence_count = !formula_occurrence_count;
    unique_formula_count = List.length (List.sort_uniq Stdlib.compare !formulas);
  }

let ir_pass_name = function
  | Orchestration.Pre_pass -> "pre"
  | Orchestration.Product_reachability_pass -> "product_reachability"
  | Orchestration.Post_pass -> "post"
  | Orchestration.Temporal_lower_pass -> "temporal_lower"

let record_ir_fact_family (family : Ir_fact_family_metrics.snapshot) =
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
  imports : string list;
  parse_info : Flow_info.parse_info;
  proof_case_program : Proof_case_program.t;
}

let prepare_program
    ~(proof_optimizations : Pipeline_config.proof_optimizations)
    ~(imports : string list) ~(parse_info : Flow_info.parse_info)
    ~(verification_model : Verification_model.program_model) :
    (prepared_program, Pipeline_error.t) result =
  try
    let p_model = verification_model in
    match reject_calls p_model with
    | Error _ as err -> err
    | Ok () ->
    let t_partition = Unix.gettimeofday () in
    let partition_result =
      p_model
      |> Proof_case_program.minimal
      |> Contract_partition.apply
        ~strategy:
          proof_optimizations.verification.contract_partition_strategy
    in
    Runtime_metrics.record_contract_partition
      ~elapsed_s:(Unix.gettimeofday () -. t_partition);
    let* proof_case_program =
      partition_result
      |> Result.map_error (fun msg -> Pipeline_error.Flow_error msg)
    in
    Ok
      {
        imports;
        parse_info;
        proof_case_program;
      }
  with exn -> Error (Pipeline_error.Flow_error (Printexc.to_string exn))

let build_snapshot_from_supplied_automata
    ~(collect_instrumentation_info : bool)
    ~(collect_ir_metrics : bool)
    ~(proof_encoding : Pipeline_config.proof_encoding)
    ~(proof_optimizations : Pipeline_config.proof_optimizations)
    ~(prepared : prepared_program)
    ~(automata :
       (Core_syntax.ident * Automaton_types.automata_spec) list)
    ~(automata_info : Flow_info.automata_info) :
    (Runtime_snapshot.pipeline_snapshot, Pipeline_error.t)
    result =
  try
    let imports = prepared.imports in
    let parse_info = prepared.parse_info in
    let proof_case_program = prepared.proof_case_program in
    let t_product = Unix.gettimeofday () in
    let reference_input : Orchestration.reference_product_input =
      {
        proof_case_program;
        automata;
      }
    in
    let reference_product =
      match Orchestration.build_reference_product reference_input with
      | Error msg -> Error (Pipeline_error.Flow_error msg)
      | Ok reference_product ->
          Runtime_metrics.record_product ~elapsed_s:(Unix.gettimeofday () -. t_product);
          Ok reference_product
    in
    match reference_product with
    | Error _ as err -> err
    | Ok reference_product -> (
        let product_nodes = reference_product.nodes in
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
          | Orchestration.Pre_pass -> Runtime_metrics.record_pre ~elapsed_s
          | Orchestration.Product_reachability_pass ->
              Runtime_metrics.record_product_reachability ~elapsed_s
          | Orchestration.Post_pass -> Runtime_metrics.record_post ~elapsed_s
          | Orchestration.Temporal_lower_pass ->
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
        let pass_observer : Orchestration.pass_observer =
          {
            before_historical = (fun _ nodes -> begin_pass nodes);
            after_historical = finish_historical;
            before_lowering = (fun _ nodes -> begin_pass nodes);
            after_lowering = finish_lowering;
          }
        in
        let t_canonical = Unix.gettimeofday () in
        let* instrumented_product_nodes =
          Orchestration.build_instrumented_ir
            ?observe_fact_family:
              (if collect_ir_metrics then Some record_ir_fact_family else None)
            ~pass_observer
            reference_product
          |> Result.map_error (fun message ->
                 Pipeline_error.Flow_error message)
        in
        let* instrumented_product_nodes =
          instrumented_product_nodes
          |> List.map
               (fun
                 (node :
                   Orchestration.instrumented_product_node)
               ->
                 Orchestration.map_instrumented_product_node
                   (fun ir ->
                     Formula_interning.apply_node
                       ~strategy:
                         proof_optimizations.verification
                           .formula_interning_strategy
                       ir)
                   node)
          |> Result_utils.all
          |> Result.map_error (fun message ->
                 Pipeline_error.Flow_error message)
        in
        Runtime_metrics.record_canonical ~elapsed_s:(Unix.gettimeofday () -. t_canonical);
        let p_instrumentation =
          List.map
            (fun
              (node : Orchestration.instrumented_product_node)
            ->
              node.ir)
            instrumented_product_nodes
        in
        let ir_program : Ir.program_ir =
          { nodes = p_instrumentation }
        in
        let t_proof_planning = Unix.gettimeofday () in
        let partition_inputs =
          List.map
            Verification_obligations.of_instrumented_product_node
            instrumented_product_nodes
        in
        let* individual_obligations =
          Verification_obligations.build_program
            ~proof_cases:proof_case_program ~partition_inputs
          |> Result.map_error (fun message ->
                 Pipeline_error.Flow_error message)
        in
        let minimal_proof_plans =
          Verification_proof_ir.minimal_program
            individual_obligations
        in
        let* proof_plans =
          Proof_plan.apply_program
            ~strategy:
              proof_optimizations.verification.proof_plan_strategy
            minimal_proof_plans
          |> Result.map_error (fun msg ->
                 Pipeline_error.Flow_error msg)
        in
        Runtime_metrics.record_proof_planning
          ~elapsed_s:(Unix.gettimeofday () -. t_proof_planning);
        let summaries_info : Flow_info.summaries_info = { warnings = [] }
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
        | Error msg -> Error (Pipeline_error.Flow_error msg)
        | Ok instrumentation_info ->
        let asts : Runtime_snapshot.ast_flow =
          {
            imports;
            proof_case_program;
            automata;
            product_nodes;
            instrumentation = p_instrumentation;
            proof_plans;
          }
        in
        let infos : Runtime_snapshot.flow_infos =
          {
            parse = Some parse_info;
            automata_generation = Some automata_info;
            summaries = Some summaries_info;
            instrumentation = instrumentation_info;
          }
        in
        let snapshot : Runtime_snapshot.pipeline_snapshot =
          { asts; infos; proof_encoding; proof_optimizations }
        in
        Ok snapshot)
  with exn -> Error (Pipeline_error.Flow_error (Printexc.to_string exn))
