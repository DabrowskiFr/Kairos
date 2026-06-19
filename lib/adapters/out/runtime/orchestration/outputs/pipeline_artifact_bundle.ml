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

open Core_syntax
open Pretty

let ( let* ) = Result.bind
module Info_helpers = Instrumentation_info_helpers

type t = {
  kernel_ir_nodes : Proof_kernel_types.node_ir list;
  exported_node_summaries : Proof_kernel_types.exported_node_summary_ir list;
  guarantee_automaton_text : string;
  assume_automaton_text : string;
  product_text : string;
  canonical_text : string;
  obligations_map_text_raw : string;
  guarantee_automaton_dot : string;
  assume_automaton_dot : string;
  product_dot : string;
  canonical_dot : string;
}

type node_artifacts = {
  kernel_ir : Proof_kernel_types.node_ir;
  exported_summary : Proof_kernel_types.exported_node_summary_ir;
  require_graph : Automata_graph_render.graph;
  ensures_graph : Automata_graph_render.graph;
  product_graph : Automata_graph_render.graph;
}

let lower_guard_for_kernel ~(node_name : ident)
    ~(temporal_bindings : Pre_k_lowering.temporal_binding list) ~(context : string)
    (guard : Core_syntax.hexpr) : (Core_syntax.hexpr, string) result =
  match Pre_k_lowering.lower_fo_formula_temporal_bindings ~temporal_bindings guard with
  | Some lowered -> Ok lowered
  | None ->
      Error
        (Printf.sprintf
           "Unable to lower temporal guard (%s) in product analysis for node %s: %s"
           context node_name (string_of_fo guard))

let lower_transition_for_kernel ~(node_name : ident)
    ~(temporal_bindings : Pre_k_lowering.temporal_binding list) ~(context : string)
    ((src, guard, dst) : Automaton_types.transition) :
    (Automaton_types.transition, string) result =
  let* guard = lower_guard_for_kernel ~node_name ~temporal_bindings ~context guard in
  Ok (src, guard, dst)

let lower_product_step_for_kernel ~(node_name : ident)
    ~(temporal_bindings : Pre_k_lowering.temporal_binding list)
    (step : Product_types.product_step) : (Product_types.product_step, string) result =
  let* prog_guard =
    lower_guard_for_kernel ~node_name ~temporal_bindings ~context:"program guard"
      step.prog_guard
  in
  let* assume_guard =
    lower_guard_for_kernel ~node_name ~temporal_bindings ~context:"assume guard"
      step.assume_guard
  in
  let* guarantee_guard =
    lower_guard_for_kernel ~node_name ~temporal_bindings ~context:"guarantee guard"
      step.guarantee_guard
  in
  let* assume_edge =
    lower_transition_for_kernel ~node_name ~temporal_bindings ~context:"assume edge"
      step.assume_edge
  in
  let* guarantee_edge =
    lower_transition_for_kernel ~node_name ~temporal_bindings ~context:"guarantee edge"
      step.guarantee_edge
  in
  Ok { step with prog_guard; assume_guard; guarantee_guard; assume_edge; guarantee_edge }

let lower_analysis_for_kernel ~(node : Ir.node_ir)
    ~(analysis : Temporal_automata.node_data) :
    (Temporal_automata.node_data, string) result =
  let temporal_bindings = Ir_formula.temporal_bindings_of_node node in
  let node_name = node.semantics.sem_nname in
  let* assume_grouped_edges =
    analysis.assume_grouped_edges
    |> List.map
         (lower_transition_for_kernel ~node_name ~temporal_bindings ~context:"assume automaton")
    |> Result_utils.all
  in
  let* guarantee_grouped_edges =
    analysis.guarantee_grouped_edges
    |> List.map
         (lower_transition_for_kernel ~node_name ~temporal_bindings
            ~context:"guarantee automaton")
    |> Result_utils.all
  in
  let* steps =
    analysis.exploration.steps
    |> List.map (lower_product_step_for_kernel ~node_name ~temporal_bindings)
    |> Result_utils.all
  in
  Ok
    {
      analysis with
      assume_grouped_edges;
      guarantee_grouped_edges;
      exploration = { analysis.exploration with steps };
    }

let build_node_artifacts ~(source_node : Verification_model.node_model)
    ~(analysis : Temporal_automata.node_data) (node : Ir.node_ir) :
    (node_artifacts, string) result =
  let* analysis_for_kernel = lower_analysis_for_kernel ~node ~analysis in
  let kernel_output =
    Proof_kernel_pass.compile_node
      {
        Proof_kernel_pass.node_name = node.semantics.sem_nname;
        source_node;
        node;
        analysis = analysis_for_kernel;
      }
  in
  let require_graph =
    Automata_graph_render.render_require_automaton ~node_name:node.semantics.sem_nname
      ~analysis
  in
  let ensures_graph =
    Automata_graph_render.render_ensures_automaton ~node_name:node.semantics.sem_nname
      ~analysis
  in
  let product_graph =
    Automata_graph_render.render_product ~node_name:node.semantics.sem_nname ~analysis
  in
  Ok
    {
      kernel_ir = kernel_output.normalized_ir;
      exported_summary = kernel_output.exported_summary;
      require_graph;
      ensures_graph;
      product_graph;
    }

let first_non_empty (xs : string list) : string =
  match List.find_opt (fun s -> String.trim s <> "") xs with Some s -> s | None -> ""

let join_non_empty (xs : string list) : string =
  xs
  |> List.filter (fun s -> String.trim s <> "")
  |> String.concat "\n\n"

let artifact_kobj ~(asts : Runtime_snapshot.ast_flow)
    ~(nodes : Proof_kernel_types.exported_node_summary_ir list) : Kairos_object.t =
  {
    Kairos_object.metadata =
      {
        format = Kairos_object.current_format;
        format_version = Kairos_object.current_version;
        backend_agnostic = true;
        source_path = None;
        source_hash = None;
        imports = asts.imports;
      };
    nodes;
  }

let string_of_product_state (st : Proof_kernel_types.product_state_ir) =
  Printf.sprintf "(P=%s,A=%d,G=%d)" st.prog_state st.assume_state_index
    st.guarantee_state_index

let string_of_step_kind = function
  | Proof_kernel_types.StepSafe -> "safe"
  | Proof_kernel_types.StepBadAssumption -> "bad_assumption"
  | Proof_kernel_types.StepBadGuarantee -> "bad_guarantee"

let string_of_origin = function
  | Proof_kernel_types.OriginSourceProductSummary -> "source-product-summary"
  | Proof_kernel_types.OriginPhaseStepPreSummary -> "phase-step-pre"
  | Proof_kernel_types.OriginPhaseStepSummary -> "phase-step"
  | Proof_kernel_types.OriginSafety -> "safety"
  | Proof_kernel_types.OriginInitNodeInvariant -> "init-node-invariant"
  | Proof_kernel_types.OriginInitAutomatonCoherence -> "init-automaton-coherence"
  | Proof_kernel_types.OriginPropagationNodeInvariant -> "propagation-node-invariant"
  | Proof_kernel_types.OriginPropagationAutomatonCoherence ->
      "propagation-automaton-coherence"

let string_of_time = function
  | Proof_kernel_types.CurrentTick -> "current"
  | Proof_kernel_types.PreviousTick -> "previous"
  | Proof_kernel_types.StepTickContext -> "step"

let string_of_rel_desc = function
  | Proof_kernel_types.RelFactProgramState st -> "state = " ^ st
  | Proof_kernel_types.RelFactGuaranteeState idx ->
      Printf.sprintf "guarantee_state = %d" idx
  | Proof_kernel_types.RelFactPhaseFormula fo
  | Proof_kernel_types.RelFactFormula fo ->
      string_of_fo fo
  | Proof_kernel_types.RelFactFalse -> "false"

let string_of_rel_fact (fact : Proof_kernel_types.relational_clause_fact_ir) =
  Printf.sprintf "%s:%s" (string_of_time fact.time) (string_of_rel_desc fact.desc)

let string_of_rel_clause (clause : Proof_kernel_types.relational_generated_clause_ir) =
  let side facts =
    match facts with
    | [] -> "true"
    | xs -> xs |> List.map string_of_rel_fact |> String.concat "; "
  in
  Printf.sprintf "[%s] %s ==> %s" (string_of_origin clause.origin)
    (side clause.hypotheses) (side clause.conclusions)

let helper_prefix_of_step (step : Proof_kernel_types.product_step_ir) =
  Printf.sprintf "step_%s_ps_%s_a%d_g%d_%s_*"
    (String.lowercase_ascii step.program_transition_id)
    (String.lowercase_ascii step.src.prog_state)
    step.src.assume_state_index step.src.guarantee_state_index
    (string_of_step_kind step.step_kind)

let render_obligations_map_node
    (node : Proof_kernel_types.exported_node_summary_ir) : string =
  let ir = node.normalized_ir in
  let transition_by_id = Hashtbl.create 16 in
  List.iter
    (fun (tr : Proof_kernel_types.reactive_transition_ir) ->
      Hashtbl.replace transition_by_id tr.transition_id tr)
    ir.reactive_program.transitions;
  let render_summary idx (summary : Proof_kernel_types.proof_step_summary_ir) =
    match summary.steps with
    | [] -> []
    | step :: _ ->
        let transition =
          match Hashtbl.find_opt transition_by_id step.program_transition_id with
          | Some tr ->
              Printf.sprintf "%s -> %s" tr.src_state tr.dst_state
          | None -> step.program_transition_id
        in
        let dsts =
          summary.steps
          |> List.map (fun (s : Proof_kernel_types.product_step_ir) ->
                 string_of_product_state s.dst)
          |> List.sort_uniq String.compare
          |> String.concat ", "
        in
        [
          Printf.sprintf "summary %03d" (idx + 1);
          "  node: " ^ node.signature.node_name;
          "  why3-helper-prefix: " ^ helper_prefix_of_step step;
          "  source-transition: " ^ transition;
          "  product-source: " ^ string_of_product_state step.src;
          "  product-destinations: " ^ dsts;
          "  kind: " ^ string_of_step_kind step.step_kind;
          Printf.sprintf "  grouped-product-steps: %d" (List.length summary.steps);
          Printf.sprintf "  entry-clauses: %d" (List.length summary.entry_clauses);
        ]
        @ List.mapi
            (fun i clause ->
              Printf.sprintf "    entry[%02d]: %s" (i + 1)
                (string_of_rel_clause clause))
            summary.entry_clauses
        @
        [
          Printf.sprintf "  post-clauses: %d" (List.length summary.clauses);
        ]
        @ List.mapi
            (fun i clause ->
              Printf.sprintf "    post[%02d]: %s" (i + 1)
                (string_of_rel_clause clause))
            summary.clauses
        @ [ "" ]
  in
  String.concat "\n"
    (("Node " ^ node.signature.node_name)
     :: (ir.proof_step_summaries |> List.mapi render_summary |> List.concat))

let render_obligations_map
    (nodes : Proof_kernel_types.exported_node_summary_ir list) =
  nodes |> List.map render_obligations_map_node |> join_non_empty

let build ~(asts : Runtime_snapshot.ast_flow) : (t, string) result =
  let source_nodes_model = Info_helpers.source_nodes_by_name asts.automata_generation in
  let source_node_of_name (node_name : ident) : (Verification_model.node_model, string) result =
    match List.assoc_opt node_name source_nodes_model with
    | Some node -> Ok node
    | None -> Error (Printf.sprintf "Missing source model node for IR node %s" node_name)
  in
  let* analyses = Info_helpers.build_analyses ~automata:asts.automata ~source_nodes:source_nodes_model in
  let* node_artifacts =
    asts.instrumentation
    |> List.map (fun (node : Ir.node_ir) ->
           let* source_node = source_node_of_name node.semantics.sem_nname in
           let* analysis = Info_helpers.analysis_of_node ~analyses node in
           build_node_artifacts ~source_node ~analysis node)
    |> Result_utils.all
  in
  let kernel_ir_nodes = List.map (fun (n : node_artifacts) -> n.kernel_ir) node_artifacts in
  let exported_node_summaries =
    List.map (fun (n : node_artifacts) -> n.exported_summary) node_artifacts
  in
  let guarantee_automaton_text =
    join_non_empty
      (List.map (fun (n : node_artifacts) -> n.ensures_graph.labels) node_artifacts)
  in
  let assume_automaton_text =
    join_non_empty
      (List.map (fun (n : node_artifacts) -> n.require_graph.labels) node_artifacts)
  in
  let product_text =
    join_non_empty
      (List.map (fun (n : node_artifacts) -> n.product_graph.labels) node_artifacts)
  in
  let guarantee_automaton_dot =
    first_non_empty
      (List.map (fun (n : node_artifacts) -> n.ensures_graph.dot) node_artifacts)
  in
  let assume_automaton_dot =
    first_non_empty
      (List.map (fun (n : node_artifacts) -> n.require_graph.dot) node_artifacts)
  in
  let product_dot =
    first_non_empty
      (List.map (fun (n : node_artifacts) -> n.product_graph.dot) node_artifacts)
  in
  let artifact_obj = artifact_kobj ~asts ~nodes:exported_node_summaries in
  Ok
    {
      kernel_ir_nodes;
      exported_node_summaries;
      guarantee_automaton_text;
      assume_automaton_text;
      product_text;
      canonical_text = Kairos_object.render_product_summaries artifact_obj;
      obligations_map_text_raw = render_obligations_map exported_node_summaries;
      guarantee_automaton_dot;
      assume_automaton_dot;
      product_dot;
      canonical_dot = "";
    }
