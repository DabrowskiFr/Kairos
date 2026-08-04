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

(** Kr_verification_orchestration entrypoint for domain IR construction.

    The reference-product entry point names the correction-critical path from
    an elaborated program plus supplied automata to product summaries. The
    instrumentation passes remain separate: they are useful for proof/backend
    construction, but they must not be confused with external tool choices,
    dumps, profiling, or backend-specific grouping. *)

open Kr_verification_automata_types

(** Helper value. *)

let ( let* ) = Result.bind

let rec all_results = function
  | [] -> Ok []
  | result :: rest ->
      let* value = result in
      let* values = all_results rest in
      Ok (value :: values)

(** Type [reference_product_input]. *)

type reference_product_input = {
  proof_case_program : Kr_verification_cases.t;
  automata : (Kr_domain_core_syntax.ident * automata_spec) list;
  reachability_strategy : Kr_verification_reachability.strategy;
}

(** Type [reference_product]. *)

type product_node = {
  proof_case : Kr_verification_cases.proof_case;
  analysis : Kr_verification_temporal_automata.node_data;
  reachability : Kr_verification_reachability.t;
  ir : Kr_domain_core_syntax.historical Kr_verification_ir.node_ir;
}

type instrumented_product_node = {
  proof_case : Kr_verification_cases.proof_case;
  ir : Kr_domain_core_syntax.history_free Kr_verification_ir.node_ir;
}

type reference_product = {
  nodes : product_node list;
}

(** Type [instrumented_ir_pass]. *)

type instrumented_ir_pass =
  | Pre_pass
  | Post_pass
  | Temporal_lower_pass

(** Read-only observation hooks around historical enrichment and the typed
    temporal-lowering boundary. The callbacks cannot replace pass results. *)
type pass_observer = {
  before_historical :
    instrumented_ir_pass ->
    Kr_domain_core_syntax.historical Kr_verification_ir.node_ir list ->
    unit;
  after_historical :
    instrumented_ir_pass ->
    Kr_domain_core_syntax.historical Kr_verification_ir.node_ir list ->
    unit;
  before_lowering :
    instrumented_ir_pass ->
    Kr_domain_core_syntax.historical Kr_verification_ir.node_ir list ->
    unit;
  after_lowering :
    instrumented_ir_pass ->
    Kr_domain_core_syntax.history_free Kr_verification_ir.node_ir list ->
    unit;
}

let silent_pass_observer =
  {
    before_historical = (fun _ _ -> ());
    after_historical = (fun _ _ -> ());
    before_lowering = (fun _ _ -> ());
    after_lowering = (fun _ _ -> ());
  }

let erase_pre_fields
    (nodes : Kr_domain_core_syntax.historical Kr_verification_ir.node_ir list) =
  List.map
    (fun (node : Kr_domain_core_syntax.historical Kr_verification_ir.node_ir) ->
      {
        node with
        summaries =
          List.map
            (fun
              (summary :
                Kr_domain_core_syntax.historical
                Kr_verification_ir.product_step_summary)
            ->
              {
                summary with
                propagation_requires = [];
                requires = [];
              })
            node.summaries;
      })
    nodes

let erase_ensures
    (nodes : Kr_domain_core_syntax.historical Kr_verification_ir.node_ir list) =
  List.map
    (fun (node : Kr_domain_core_syntax.historical Kr_verification_ir.node_ir) ->
      {
        node with
        summaries =
          List.map
            (fun
              (summary :
                Kr_domain_core_syntax.historical
                Kr_verification_ir.product_step_summary)
            ->
              { summary with ensures = [] })
            node.summaries;
      })
    nodes

let rec is_prefix equal prefix values =
  match (prefix, values) with
  | [], _ -> true
  | _, [] -> false
  | left :: prefix, right :: values ->
      equal left right && is_prefix equal prefix values

let ensures_are_extended before after =
  List.for_all2
    (fun before_node after_node ->
      List.for_all2
        (fun before_summary after_summary ->
          is_prefix ( = ) before_summary.Kr_verification_ir.ensures
            after_summary.Kr_verification_ir.ensures)
        before_node.Kr_verification_ir.summaries after_node.Kr_verification_ir.summaries)
    before after

let validate_pre_delta before after =
  if erase_pre_fields before = erase_pre_fields after then Ok ()
  else
    Error
      "Pre changed a field outside propagation_requires/requires"

let validate_ensures_delta ~pass_name before after =
  if erase_ensures before <> erase_ensures after then
    Error
      (Printf.sprintf
         "%s changed a field outside ensures" pass_name)
  else if not (ensures_are_extended before after) then
    Error
      (Printf.sprintf
         "%s removed or reordered an existing ensure" pass_name)
  else Ok ()

type summary_lowering_shape = {
  trace : Kr_verification_ir.product_step_summary_trace;
  program_step : Kr_verification_ir.transition;
  product_src : Kr_verification_ir.product_state;
  assume_destination_state_index :
    Kr_verification_ir_shared.automaton_state_index;
  propagation_meta : Kr_verification_ir.formula_meta list;
  requires_meta : Kr_verification_ir.formula_meta list;
  ensures_meta : Kr_verification_ir.formula_meta list;
  elaboration_checks_meta : Kr_verification_ir.formula_meta list;
  product_cases : (Kr_verification_ir.product_state * Kr_verification_ir.formula_meta) list;
}

type node_lowering_shape = {
  semantics : Kr_verification_ir.node_signature;
  source_info : Kr_verification_ir.source_info;
  summaries : summary_lowering_shape list;
}

let formula_metadata formulas =
  List.map
    (fun (formula : _ Kr_verification_ir.summary_formula) -> formula.meta)
    formulas

let summary_lowering_shape :
    type phase.
    phase Kr_verification_ir.product_step_summary ->
    summary_lowering_shape =
 fun summary ->
  {
    trace = summary.trace;
    program_step = summary.identity.program_step;
    product_src = Kr_verification_ir.product_source summary;
    assume_destination_state_index =
      summary.identity
        .assume_destination_state_index;
    propagation_meta =
      formula_metadata summary.propagation_requires;
    requires_meta = formula_metadata summary.requires;
    ensures_meta = formula_metadata summary.ensures;
    elaboration_checks_meta =
      formula_metadata summary.elaboration_checks;
    product_cases =
      List.map
        (fun (case : phase Kr_verification_ir.product_case) ->
          (Kr_verification_ir.product_destination summary case,
           case.guarantee_guard.meta))
        summary.product_cases;
  }

let node_lowering_shape :
    type phase. phase Kr_verification_ir.node_ir -> node_lowering_shape =
 fun node ->
  {
    semantics = node.semantics;
    source_info = node.source_info;
    summaries = List.map summary_lowering_shape node.summaries;
  }

let validate_temporal_lower_delta before after =
  if
    List.map node_lowering_shape before
    <> List.map node_lowering_shape after
  then
    Error
      "Temporal_lower changed product topology, formula occurrences, or \
       metadata"
  else if
    not
      (List.for_all2
         (fun before_node after_node ->
           after_node.Kr_verification_ir.temporal_layout
           = Temporal_lower.required_temporal_layout before_node)
         before after)
  then Error "Temporal_lower produced an inconsistent temporal layout"
  else Ok ()

(** [build_reference_product] helper value. *)

let build_reference_product
    ({ proof_case_program; automata; reachability_strategy } :
      reference_product_input) :
    (reference_product, string) result =
  let* analyzed_nodes =
    From_model.analyze_model_program ~automata
      (Kr_verification_cases.program proof_case_program)
  in
  let* nodes =
    analyzed_nodes
    |> List.map (fun (node : From_model.analyzed_node) ->
           let proof_case_name = node.model.node_name in
           match
             Kr_verification_cases.find_case proof_case_program
               proof_case_name
           with
           | Some proof_case ->
               let initial_state = node.analysis.exploration.initial_state in
               let reachability =
                 Kr_verification_reachability.build
                   ~strategy:reachability_strategy ~initial_state
                   ~node:node.ir
               in
               Ok
                 {
                   proof_case;
                   analysis = node.analysis;
                   reachability;
                   ir = node.ir;
                 }
           | None ->
               Error
                 (Printf.sprintf
                    "Missing core proof case for product node %s"
                    proof_case_name))
    |> all_results
  in
  Ok { nodes }

(** [build_instrumented_ir] helper value. *)

let build_instrumented_ir
    ?observe_fact_family
    ?(pass_observer = silent_pass_observer)
    (reference_product : reference_product) :
    (instrumented_product_node list, string) result =
  let product_nodes = reference_product.nodes in
  let proof_cases =
    List.map
      (fun (node : product_node) -> node.proof_case)
      product_nodes
  in
  let initial_nodes =
    List.map (fun (node : product_node) -> node.ir) product_nodes
  in
  let validate_pass_nodes pass_name nodes =
    if List.length proof_cases <> List.length nodes then
      Error
        (Printf.sprintf
           "Verification pass '%s' changed the number of proof-case IR nodes \
            from %d to %d"
           pass_name (List.length proof_cases) (List.length nodes))
    else
      List.map2
        (fun
          (proof_case : Kr_verification_cases.proof_case)
          node
        ->
      From_model.validate_node_origin ~model:proof_case.model node
          |> Result.map_error (fun message ->
                 Printf.sprintf
                   "Verification pass '%s' broke proof-case provenance: %s"
                   pass_name message))
        proof_cases nodes
      |> all_results
      |> Result.map (fun _ -> ())
  in
  let* () = validate_pass_nodes "reference_product" initial_nodes in
  let product_invariants =
    List.map2
      (fun (product_node : product_node)
           (node : Kr_domain_core_syntax.historical Kr_verification_ir.node_ir) ->
        [
          Product_invariant.of_reachability
            product_node.reachability;
          Product_invariant.of_characteristics
            (let initial_state =
               product_node.analysis.exploration.initial_state
             in
             Kr_verification_characteristics.build ~initial_state ~node);
        ])
      product_nodes initial_nodes
  in
  pass_observer.before_historical Pre_pass initial_nodes;
  let pre_nodes =
    Pre.run_program ?observe_family:observe_fact_family
      ~product_invariants initial_nodes
  in
  pass_observer.after_historical Pre_pass pre_nodes;
  let* () = validate_pre_delta initial_nodes pre_nodes in
  let* () = validate_pass_nodes "pre" pre_nodes in
  pass_observer.before_historical Post_pass pre_nodes;
  let post_nodes =
    Post.run_program ?observe_family:observe_fact_family
      ~product_invariants pre_nodes
  in
  pass_observer.after_historical Post_pass post_nodes;
  let* () =
    validate_ensures_delta ~pass_name:"Post" pre_nodes
      post_nodes
  in
  let* () = validate_pass_nodes "post" post_nodes in
  pass_observer.before_lowering Temporal_lower_pass post_nodes;
  let backend_nodes =
    Temporal_lower.run_program post_nodes
  in
  pass_observer.after_lowering Temporal_lower_pass backend_nodes;
  let* () =
    validate_temporal_lower_delta post_nodes backend_nodes
  in
  let* () = validate_pass_nodes "temporal_lower" backend_nodes in
  Ok
    (List.map2
       (fun (product_node : product_node) ir ->
         {
           proof_case = product_node.proof_case;
           ir;
         })
       product_nodes backend_nodes)
