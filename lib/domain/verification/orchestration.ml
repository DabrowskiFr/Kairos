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

(** Orchestration entrypoint for domain IR construction.

    The reference-product entry point names the correction-critical path from
    an elaborated program plus supplied automata to product summaries. The
    instrumentation passes remain separate: they are useful for proof/backend
    construction, but they must not be confused with external tool choices,
    dumps, profiling, or backend-specific grouping. *)

open Automaton_types

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
  proof_case_program : Proof_case_program.t;
  automata : (Core_syntax.ident * automata_spec) list;
}

(** Type [reference_product]. *)

type product_node = {
  proof_case : Proof_case_program.proof_case;
  analysis : Temporal_automata.node_data;
  ir : Core_syntax.historical Ir.node_ir;
}

type instrumented_product_node = {
  proof_case : Proof_case_program.proof_case;
  ir : Core_syntax.history_free Ir.node_ir;
}

type reference_product = {
  nodes : product_node list;
}

let map_instrumented_product_node transform
    (node : instrumented_product_node) =
  let ir = transform node.ir in
  if ir <> node.ir then
    Error
      "Instrumented proof-case IR transformation changed the structural IR"
  else
    let* () =
      From_model.validate_node_origin ~model:node.proof_case.model ir
      |> Result.map_error (fun message ->
             "Instrumented proof-case IR transformation broke provenance: "
             ^ message)
    in
    Ok { node with ir }

(** Type [instrumented_ir_pass]. *)

type instrumented_ir_pass =
  | Pre_pass
  | Product_reachability_pass
  | Post_pass
  | Temporal_lower_pass

(** Read-only observation hooks around historical enrichment and the typed
    temporal-lowering boundary. The callbacks cannot replace pass results. *)
type pass_observer = {
  before_historical :
    instrumented_ir_pass ->
    Core_syntax.historical Ir.node_ir list ->
    unit;
  after_historical :
    instrumented_ir_pass ->
    Core_syntax.historical Ir.node_ir list ->
    unit;
  before_lowering :
    instrumented_ir_pass ->
    Core_syntax.historical Ir.node_ir list ->
    unit;
  after_lowering :
    instrumented_ir_pass ->
    Core_syntax.history_free Ir.node_ir list ->
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
    (nodes : Core_syntax.historical Ir.node_ir list) =
  List.map
    (fun (node : Core_syntax.historical Ir.node_ir) ->
      {
        node with
        summaries =
          List.map
            (fun
              (summary :
                Core_syntax.historical
                Ir.product_step_summary)
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
    (nodes : Core_syntax.historical Ir.node_ir list) =
  List.map
    (fun (node : Core_syntax.historical Ir.node_ir) ->
      {
        node with
        summaries =
          List.map
            (fun
              (summary :
                Core_syntax.historical
                Ir.product_step_summary)
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
          is_prefix ( = ) before_summary.Ir.ensures
            after_summary.Ir.ensures)
        before_node.Ir.summaries after_node.Ir.summaries)
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
  trace : Ir.product_step_summary_trace;
  program_step : Ir.transition;
  product_src : Ir.product_state;
  propagation_meta : Ir.formula_meta list;
  requires_meta : Ir.formula_meta list;
  ensures_meta : Ir.formula_meta list;
  elaboration_checks_meta : Ir.formula_meta list;
  safe_cases : (Ir.product_state * Ir.formula_meta) list;
  unsafe_cases : (Ir.product_state * Ir.formula_meta) list;
}

type node_lowering_shape = {
  semantics : Ir.node_signature;
  source_info : Ir.source_info;
  summaries : summary_lowering_shape list;
  init_invariant_meta : Ir.formula_meta list;
}

let formula_metadata formulas =
  List.map
    (fun (formula : _ Ir.summary_formula) -> formula.meta)
    formulas

let summary_lowering_shape :
    type phase.
    phase Ir.product_step_summary ->
    summary_lowering_shape =
 fun summary ->
  {
    trace = summary.trace;
    program_step = summary.identity.program_step;
    product_src = summary.identity.product_src;
    propagation_meta =
      formula_metadata summary.propagation_requires;
    requires_meta = formula_metadata summary.requires;
    ensures_meta = formula_metadata summary.ensures;
    elaboration_checks_meta =
      formula_metadata summary.elaboration_checks;
    safe_cases =
      List.map
        (fun (case : phase Ir.safe_product_case) ->
          (case.product_dst, case.admissible_guard.meta))
        summary.safe_cases;
    unsafe_cases =
      List.map
        (fun (case : phase Ir.unsafe_product_case) ->
          (case.product_dst, case.excluded_guard.meta))
        summary.unsafe_cases;
  }

let node_lowering_shape :
    type phase. phase Ir.node_ir -> node_lowering_shape =
 fun node ->
  {
    semantics = node.semantics;
    source_info = node.source_info;
    summaries = List.map summary_lowering_shape node.summaries;
    init_invariant_meta =
      formula_metadata node.init_invariant_goals;
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
           after_node.Ir.temporal_layout
           = Temporal_lower.required_temporal_layout before_node)
         before after)
  then Error "Temporal_lower produced an inconsistent temporal layout"
  else Ok ()

(** [build_reference_product] helper value. *)

let build_reference_product
    ({ proof_case_program; automata } : reference_product_input) :
    (reference_product, string) result =
  let* analyzed_nodes =
    From_model.analyze_model_program ~automata
      (Proof_case_program.program proof_case_program)
  in
  let* nodes =
    analyzed_nodes
    |> List.map (fun (node : From_model.analyzed_node) ->
           let proof_case_name = node.model.node_name in
           match
             Proof_case_program.find_case proof_case_program
               proof_case_name
           with
           | Some proof_case ->
               Ok
                 {
                   proof_case;
                   analysis = node.analysis;
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
          (proof_case : Proof_case_program.proof_case)
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
  let product_characteristics =
    initial_nodes
    |> List.map (fun (node : Core_syntax.historical Ir.node_ir) ->
           Product_characteristics.build ~node)
  in
  pass_observer.before_historical Pre_pass initial_nodes;
  let pre_nodes =
    Pre.run_program ?observe_family:observe_fact_family
      ~product_characteristics initial_nodes
  in
  pass_observer.after_historical Pre_pass pre_nodes;
  let* () = validate_pre_delta initial_nodes pre_nodes in
  let* () = validate_pass_nodes "pre" pre_nodes in
  pass_observer.before_historical Product_reachability_pass
    pre_nodes;
  let reachable_nodes =
    Product_reachability.run_program pre_nodes
  in
  pass_observer.after_historical Product_reachability_pass
    reachable_nodes;
  let* () =
    validate_ensures_delta ~pass_name:"Product_reachability"
      pre_nodes reachable_nodes
  in
  let* () =
    validate_pass_nodes "product_reachability" reachable_nodes
  in
  pass_observer.before_historical Post_pass reachable_nodes;
  let post_nodes =
    Post.run_program ?observe_family:observe_fact_family
      ~product_characteristics reachable_nodes
  in
  pass_observer.after_historical Post_pass post_nodes;
  let* () =
    validate_ensures_delta ~pass_name:"Post" reachable_nodes
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
       (fun proof_case ir -> { proof_case; ir })
       proof_cases backend_nodes)
