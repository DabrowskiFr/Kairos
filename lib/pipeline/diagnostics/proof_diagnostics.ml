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

open Ast

module Abs = Ir

module Types = Pipeline_types

type formula_record = {
  oid : int;
  source : string;
  node : string option;
  transition : string option;
  obligation_kind : string;
  obligation_family : string option;
  obligation_category : string option;
  loc : Ast.loc option;
}

let build_formula_records (p_obc : Abs.node_ir list) : formula_record list =
  let records = ref [] in
  let add record = records := record :: !records in
  List.iter
    (fun (node : Abs.node_ir) ->
      let node_name = node.semantics.sem_nname in
      List.iter
        (fun (goal : Abs.summary_formula) ->
          add
            {
              oid = goal.meta.oid;
              source = Printf.sprintf "%s: <init>" node_name;
              node = Some node_name;
              transition = None;
              obligation_kind = "initial_invariant_goal";
              obligation_family =
                Some
                  (Obligation_taxonomy.family_name
                     Obligation_taxonomy.FamInitialInvariantGoal);
              obligation_category =
                Some (Obligation_taxonomy.category_name Obligation_taxonomy.CatInitialGoal);
              loc = goal.meta.loc;
            })
        node.init_invariant_goals;
      ())
    p_obc;
  List.rev !records

let formula_record_table (records : formula_record list) =
  let tbl = Hashtbl.create (List.length records * 2 + 1) in
  List.iter (fun record -> Hashtbl.replace tbl record.oid record) records;
  tbl

let unique_preserve_order xs =
  let seen = Hashtbl.create 16 in
  List.filter
    (fun x ->
      if x = "" || Hashtbl.mem seen x then false
      else (
        Hashtbl.replace seen x ();
        true))
    xs

let diagnostic_for_trace ~(status : string) ~(record : formula_record option) ~(goal_text : string)
    ~(native_core : Why_contract_prove.native_unsat_core option)
    ~(native_probe : Why_contract_prove.native_solver_probe option) : Types.proof_diagnostic =
  let goal_symbols = [] in
  let kairos_core_hypotheses = [] in
  let why3_noise_hypotheses = [] in
  let relevant_hypotheses = kairos_core_hypotheses in
  let context_hypotheses = kairos_core_hypotheses in
  let unused_hypotheses = [] in
  let status_norm = String.lowercase_ascii (String.trim status) in
  let native_probe_status =
    Option.map (fun (probe : Why_contract_prove.native_solver_probe) -> probe.status) native_probe
  in
  let native_probe_detail =
    Option.bind native_probe (fun (probe : Why_contract_prove.native_solver_probe) -> probe.detail)
  in
  let native_probe_model =
    Option.bind native_probe (fun (probe : Why_contract_prove.native_solver_probe) -> probe.model_text)
  in
  let category, probable_cause, missing_elements, suggestions, detail_override =
    match (status_norm, native_probe_status, native_probe_model) with
    | (_, _, Some _) ->
        ( "counterexample_found",
          Some "The native solver produced a satisfying model for the negated VC.",
          [],
          [
            "Inspect the native model first: it witnesses a concrete falsification of this obligation.";
            "Compare the model with the Source -> OBC -> Why -> VC chain to identify the missing relation.";
          ],
          Some
            (Printf.sprintf
               "Goal `%s` is falsifiable: the native solver returned a concrete model."
               goal_text) )
    | ("valid" | "proved"), _, _ ->
        ( "proved",
          Some "This VC was discharged successfully.",
          [],
          [ "Use the trace chain to inspect the obligation that was proved." ],
          Some (Printf.sprintf "Goal `%s` was proved successfully." goal_text) )
    | "timeout", _, _ ->
        ( "solver_timeout",
          Some "The solver reached its time limit before closing this VC.",
          [],
          [
            "Retry with a larger timeout to separate complexity from a genuine modeling gap.";
            "Inspect the minimal context and the SMT task to identify heavy arithmetic or quantifier interactions.";
          ],
          None )
    | "unknown", _, _ ->
        ( "solver_inconclusive",
          Some
            (match native_probe_detail with
            | Some detail ->
                Printf.sprintf "The solver returned an inconclusive result on this VC (%s)." detail
            | None -> "The solver returned an inconclusive result on this VC."),
          [],
          [
            "Inspect the VC and SMT artefacts for unsupported patterns.";
            "Try strengthening the local invariants or splitting the property into smaller clauses.";
          ],
          None )
    | "invalid", _, _ ->
        ( "counterexample_found",
          Some "The VC is falsifiable: the solver established the negated obligation as satisfiable.",
          [],
          [
            "Inspect the native model/counterexample payload first.";
            "Navigate back to Source and OBC to locate the weakest missing relation.";
          ],
          Some (Printf.sprintf "Goal `%s` is falsifiable under the current assumptions." goal_text) )
    | ("failure" | "oom"), _, _ ->
        ( (if native_probe_status = Some "solver_error" then "solver_error" else "solver_failure"),
          Some
            (match native_probe_detail with
            | Some detail ->
                Printf.sprintf
                  "The prover failed before producing a conclusive proof result (%s)."
                  detail
            | None -> "The prover failed before producing a conclusive proof result."),
          [],
          [
            "Inspect the dumped SMT task and prover configuration.";
            "Check that the selected solver/driver matches the generated theory.";
          ],
          None )
    | _ -> (
        match record with
        | Some { obligation_family = Some "no_bad_requires" | Some "no_bad_ensures"; _ } ->
            ( "no_bad_obligation",
              Some
                "The monitor/product safety obligation leading to bad state exclusion is not discharged.",
              [ "Missing compatibility assumption or monitor support invariant" ],
              [
                "Inspect the product automaton and prune reasons around the same transition.";
                "Check whether the monitor instrumentation encodes the expected bad-state exclusion.";
              ],
              None )
        | Some
            {
              obligation_family =
                Some "guarantee_propagation_requires"
                | Some "guarantee_automaton_ensures"
                | Some "state_aware_assumption_requires";
              _;
            } ->
            ( "monitor_product_incompatibility",
              Some
                "A compatibility-side obligation between the program and monitor automata is not established.",
              [ "Assumption automaton premise"; "monitor/program compatibility invariant" ],
              [
                "Inspect the Assume/Guarantee/Product automata around the referenced transition.";
                "Check whether the transition guard and monitor state relation agree.";
              ],
              None )
        | Some { obligation_family = Some "invariant_requires"; _ } ->
            ( "precondition_insufficient",
              Some "The shifted invariant is not available when entering this transition.",
              [ "A stronger incoming invariant or transition precondition" ],
              [
                "Inspect the relevant hypotheses to see which state relation is missing.";
                "Strengthen the invariant propagated into this transition.";
              ],
              None )
        | Some { obligation_family = Some "invariant_ensures_shifted"; _ } ->
            ( "invariant_not_preserved",
              Some "The transition body does not preserve the expected shifted invariant.",
              [ "A stronger post-state invariant" ],
              [
                "Inspect the minimal context and the Why snippet for the failing preservation step.";
                "Check assignments and monitor updates on this transition.";
              ],
              None )
        | Some { obligation_family = Some "initial_invariant_goal"; _ } ->
            ( "initial_invariant_missing",
              Some "The initial helper goal establishing the base invariant is not proved.",
              [ "An initial-state invariant strong enough for the first step" ],
              [
                "Inspect the source initialization and the OBC initial clause.";
                "Check whether the intended base case is encoded explicitly.";
              ],
              None )
        | Some { obligation_family = Some "transition_requires"; _ } ->
            ( "precondition_insufficient",
              Some
                "The local assumptions available before the transition do not imply the required VC premise.",
              [ "A missing transition precondition or support invariant" ],
              [
                "Inspect the relevant hypotheses slice for absent guard/state facts.";
                "If the VC depends on previous-state facts, add an explicit invariant.";
              ],
              None )
        | Some { obligation_family = Some "transition_ensures"; _ } ->
            ( "postcondition_too_strong",
              Some
                "The generated postcondition is stronger than what the current transition establishes.",
              [ "A stronger transition body invariant or a weaker postcondition" ],
              [
                "Inspect the Why and SMT artefacts to see the exact target clause.";
                "Check whether the post-state relation should be split into smaller obligations.";
              ],
              None )
        | _ ->
            ( "proof_failure",
              Some "The VC could not be discharged with the available information.",
              [],
              [
                "Inspect the Why, VC and SMT artefacts for the exact clause sent to the solver.";
                "Compare the relevant hypotheses slice with the intended transition invariant.";
              ],
              None ))
  in
  let summary =
    match record with
    | Some record ->
        if kairos_core_hypotheses <> [] then
          Printf.sprintf "%s on %s with %d Kairos hypotheses in the focused core" category
            record.source (List.length kairos_core_hypotheses)
        else if why3_noise_hypotheses <> [] then
          Printf.sprintf
            "%s on %s; failure is currently dominated by auxiliary Why3 context"
            category record.source
        else Printf.sprintf "%s on %s" category record.source
    | None -> category
  in
  let detail =
    match detail_override with
    | Some detail -> detail
    | None -> (
        match record with
        | Some record ->
            Printf.sprintf "Goal `%s` failed in `%s` (%s)." goal_text record.source
              record.obligation_kind
        | None ->
            Printf.sprintf "Goal `%s` failed without a resolved source obligation." goal_text)
  in
  let probable_cause =
    match (probable_cause, kairos_core_hypotheses, why3_noise_hypotheses) with
    | Some _, _ :: _, _ -> probable_cause
    | _, [], _ :: _ ->
        Some
          "The failure currently appears to depend more on auxiliary Why3 context than on an isolated Kairos hypothesis core."
    | _ -> probable_cause
  in
  let suggestions =
    match (native_probe_model, kairos_core_hypotheses, why3_noise_hypotheses) with
    | Some _, _, _ ->
        "Use the native counterexample as the primary debugging entry point before inspecting the broader VC."
        :: suggestions
    | None, _ :: _, _ ->
        "Inspect the instrumented Kairos core first; these hypotheses survived replay-minimization."
        :: suggestions
    | None, [], _ :: _ ->
        "Inspect the Why/VC view: the current failure is dominated by auxiliary Why3 context or solver reasoning."
        :: suggestions
    | _ -> suggestions
  in
  {
    category;
    summary;
    detail;
    probable_cause;
    missing_elements;
    goal_symbols;
    analysis_method =
      (match native_core with
      | Some core ->
          Printf.sprintf
            "Native SMT unsat core recovered from %s on hid-named assertions, then remapped to Kairos hypotheses"
            core.solver
      | None when native_probe_model <> None ->
          "Native SMT model recovered from the targeted solver on the focused VC"
      | None ->
          "Status-based diagnostic without structured sequent analysis");
    solver_detail = native_probe_detail;
    native_unsat_core_solver =
      Option.map (fun (core : Why_contract_prove.native_unsat_core) -> core.solver) native_core;
    native_unsat_core_hypothesis_ids =
      (match native_core with Some core -> core.hypothesis_ids | None -> []);
    native_counterexample_solver =
      Option.bind native_probe (fun (probe : Why_contract_prove.native_solver_probe) ->
          match probe.model_text with Some _ -> Some probe.solver | None -> None);
    native_counterexample_model = native_probe_model;
    kairos_core_hypotheses;
    why3_noise_hypotheses;
    relevant_hypotheses;
    context_hypotheses;
    unused_hypotheses;
    suggestions;
    limitations =
      [
        "The minimal context is inferred from normalized Why3 task structure, not from prover unsat cores.";
        "Native counterexample extraction currently relies on a direct Z3 SMT replay path when the targeted VC is satisfiable.";
        "Missing hypotheses are suggested from the goal shape, preserved hypothesis origins and obligation family, not from solver-produced proof objects.";
      ];
  }

let stable_goal_id goal_index why_ids =
  let ids = unique_preserve_order (List.map string_of_int why_ids) in
  match ids with
  | [] -> Printf.sprintf "vc-%03d" (goal_index + 1)
  | _ -> Printf.sprintf "vc-%03d[%s]" (goal_index + 1) (String.concat "-" ids)

let collect_origin_ids why_ids =
  let seen = Hashtbl.create 16 in
  let push acc id =
    if Hashtbl.mem seen id then acc
    else (
      Hashtbl.replace seen id ();
      id :: acc)
  in
  why_ids
  |> List.fold_left
       (fun acc id ->
         let acc = push acc id in
         List.fold_left push acc (Provenance.ancestors id))
       []
  |> List.rev

let resolve_formula_record ~(records : (int, formula_record) Hashtbl.t) ~(why_ids : int list) :
    formula_record option =
  let origin_ids = collect_origin_ids why_ids in
  List.find_map (fun id -> Hashtbl.find_opt records id) origin_ids

let source_from_record_or_state ~(record : formula_record option) =
  match record with
  | Some record -> record.source
  | None -> ""

let lookup_span table id = Hashtbl.find_opt table id

let vc_ids_of_task_goal_ids (task_goal_ids : int list list) : int list =
  List.mapi
    (fun idx ids ->
      if ids = [] then idx + 1
      else
        let vcid = Provenance.fresh_id () in
        Provenance.add_parents ~child:vcid ~parents:ids;
        vcid)
    task_goal_ids

let generic_diagnostic_for_status ~(status : string)
    (diagnostic : Types.proof_diagnostic) : Types.proof_diagnostic =
  let normalized = String.lowercase_ascii status in
  match normalized with
  | "valid" | "proved" ->
      {
        diagnostic with
        category = "proved";
        summary = "The goal was proved.";
        detail = "Kairos proved this verification condition on the standard proof path.";
        solver_detail = None;
      }
  | "pending" -> diagnostic
  | "timeout" ->
      {
        diagnostic with
        category = "solver_timeout";
        summary = "The prover timed out on this goal.";
        detail = "Re-run a focused diagnosis on this goal to inspect the Why3/SMT context in detail.";
      }
  | "unknown" ->
      {
        diagnostic with
        category = "solver_inconclusive";
        summary = "The prover returned an inconclusive result.";
        detail = "Re-run a focused diagnosis on this goal to inspect solver feedback and relevant context.";
      }
  | _ ->
      {
        diagnostic with
        category = "solver_failure";
        summary = "The goal failed on the standard proof path.";
        detail = "Run focused diagnosis on this goal to compute replay-based explanations and SMT-level details.";
      }

let apply_goal_results_to_outputs ~(out : Types.outputs)
    ~(goal_results :
       (int * string * string * float * string option * string * string option) list) :
    Types.outputs =
  let results_tbl = Hashtbl.create (List.length goal_results * 2 + 1) in
  List.iter
    (fun ((idx, _, _, _, _, _, _) as item) -> Hashtbl.replace results_tbl idx item)
    goal_results;
  let proof_traces =
    List.map
      (fun (trace : Types.proof_trace) ->
        match Hashtbl.find_opt results_tbl trace.goal_index with
        | None -> trace
        | Some (_idx, goal_name, status, time_s, dump_path, source, vc_id) ->
            {
              trace with
              goal_name;
              status;
              solver_status = status;
              time_s;
              source;
              vc_id;
              dump_path;
              diagnostic = generic_diagnostic_for_status ~status trace.diagnostic;
            })
      out.proof_traces
  in
  let goals =
    List.map
      (fun (trace : Types.proof_trace) ->
        ( trace.goal_name,
          trace.status,
          trace.time_s,
          trace.dump_path,
          trace.source,
          trace.vc_id ))
      proof_traces
  in
  { out with proof_traces; goals }
