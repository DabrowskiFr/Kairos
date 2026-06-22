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

module Json = Yojson.Safe
module PK = Proof_kernel_types
module StringMap = Map.Make (String)
module StringSet = Set.Make (String)

let json_int n = `Int n
let json_float f = `Float f
let json_string s = `String s
let json_bool b = `Bool b
let json_list f xs = `List (List.map f xs)
let json_assoc xs = `Assoc xs

let json_opt f = function None -> `Null | Some x -> f x

let count_if pred xs =
  List.fold_left (fun acc x -> if pred x then acc + 1 else acc) 0 xs

let sum_int xs = List.fold_left ( + ) 0 xs

let max_int xs =
  List.fold_left max 0 xs

let average_int xs =
  match xs with
  | [] -> 0.0
  | _ -> float_of_int (sum_int xs) /. float_of_int (List.length xs)

let rec expr_size (e : expr) =
  match e.expr with
  | ELitInt _ | ELitBool _ | ELitEnum _ | EVar _ -> 1
  | EFunCall (_, args) -> 1 + sum_int (List.map expr_size args)
  | EUn (_, inner) -> 1 + expr_size inner
  | EBin (_, a, b) | ECmp (_, a, b) -> 1 + expr_size a + expr_size b

let rec stmt_size (s : stmt) =
  match s.stmt with
  | SAssign (_, e) -> 1 + expr_size e
  | SIf (guard, then_branch, else_branch) ->
      1 + expr_size guard + sum_int (List.map stmt_size then_branch)
      + sum_int (List.map stmt_size else_branch)
  | SMatch (scrutinee, branches, default_branch) ->
      1 + expr_size scrutinee
      + sum_int
          (List.map
             (fun (_, body) -> sum_int (List.map stmt_size body))
             branches)
      + sum_int (List.map stmt_size default_branch)
  | SSkip -> 1
  | SCall (_, args, outs) -> 1 + List.length outs + sum_int (List.map expr_size args)

let rec hexpr_size (h : hexpr) =
  match h.hexpr with
  | HLitInt _ | HLitBool _ | HLitEnum _ | HVar _ | HPreK _ -> 1
  | HPred (_, args) | HFunCall (_, args) -> 1 + sum_int (List.map hexpr_size args)
  | HUn (_, inner) -> 1 + hexpr_size inner
  | HBin (_, a, b) | HCmp (_, a, b) -> 1 + hexpr_size a + hexpr_size b

let rec hexpr_max_pre_depth (h : hexpr) =
  match h.hexpr with
  | HLitInt _ | HLitBool _ | HLitEnum _ | HVar _ -> 0
  | HPreK (_, k) -> k
  | HPred (_, args) | HFunCall (_, args) -> max_int (List.map hexpr_max_pre_depth args)
  | HUn (_, inner) -> hexpr_max_pre_depth inner
  | HBin (_, a, b) | HCmp (_, a, b) ->
      max (hexpr_max_pre_depth a) (hexpr_max_pre_depth b)

let rec hexpr_free_variables (h : hexpr) =
  match h.hexpr with
  | HLitInt _ | HLitBool _ | HLitEnum _ -> StringSet.empty
  | HVar v | HPreK (v, _) -> StringSet.singleton v
  | HPred (_, args) | HFunCall (_, args) ->
      List.fold_left
        (fun acc h -> StringSet.union acc (hexpr_free_variables h))
        StringSet.empty args
  | HUn (_, inner) -> hexpr_free_variables inner
  | HBin (_, a, b) | HCmp (_, a, b) ->
      StringSet.union (hexpr_free_variables a) (hexpr_free_variables b)

let rec ltl_size = function
  | LTrue | LFalse -> 1
  | LAtom (a, _, b) -> 1 + hexpr_size a + hexpr_size b
  | LNot a | LX a | LG a -> 1 + ltl_size a
  | LAnd (a, b) | LOr (a, b) | LImp (a, b) | LW (a, b) ->
      1 + ltl_size a + ltl_size b

let rec ltl_temporal_depth = function
  | LTrue | LFalse | LAtom _ -> 0
  | LNot a -> ltl_temporal_depth a
  | LX a | LG a -> 1 + ltl_temporal_depth a
  | LAnd (a, b) | LOr (a, b) | LImp (a, b) ->
      max (ltl_temporal_depth a) (ltl_temporal_depth b)
  | LW (a, b) -> 1 + max (ltl_temporal_depth a) (ltl_temporal_depth b)

let rec ltl_max_pre_depth = function
  | LTrue | LFalse -> 0
  | LAtom (a, _, b) -> max (hexpr_max_pre_depth a) (hexpr_max_pre_depth b)
  | LNot a | LX a | LG a -> ltl_max_pre_depth a
  | LAnd (a, b) | LOr (a, b) | LImp (a, b) | LW (a, b) ->
      max (ltl_max_pre_depth a) (ltl_max_pre_depth b)

let truncate_string max_len s =
  if String.length s <= max_len then s
  else String.sub s 0 max_len ^ "..."

let starts_with ~prefix s =
  let lp = String.length prefix in
  String.length s >= lp && String.sub s 0 lp = prefix

let contains_substring s sub =
  let len_s = String.length s in
  let len_sub = String.length sub in
  let rec loop i =
    if len_sub = 0 then true
    else if i + len_sub > len_s then false
    else if String.sub s i len_sub = sub then true
    else loop (i + 1)
  in
  loop 0

type fact_stat = {
  key : string;
  hash : string;
  size : int;
  max_pre_depth : int;
  arity : int;
  mutable occurrences : int;
  mutable origins : StringSet.t;
  mutable phases : StringSet.t;
}

let new_fact_stat key h ~origin ~phase =
  {
    key;
    hash = Digest.to_hex (Digest.string key);
    size = hexpr_size h;
    max_pre_depth = hexpr_max_pre_depth h;
    arity = StringSet.cardinal (hexpr_free_variables h);
    occurrences = 1;
    origins = StringSet.singleton origin;
    phases = StringSet.singleton phase;
  }

let add_fact table ~origin ~phase h =
  let key = string_of_fo h in
  match Hashtbl.find_opt table key with
  | Some stat ->
      stat.occurrences <- stat.occurrences + 1;
      stat.origins <- StringSet.add origin stat.origins;
      stat.phases <- StringSet.add phase stat.phases
  | None -> Hashtbl.add table key (new_fact_stat key h ~origin ~phase)

let fact_stats table =
  Hashtbl.fold (fun _ stat acc -> stat :: acc) table []

let fact_repeated_cost stat = stat.size * max 0 (stat.occurrences - 1)

let compare_fact_hotness a b =
  match Int.compare (fact_repeated_cost b) (fact_repeated_cost a) with
  | 0 -> begin
      match Int.compare b.occurrences a.occurrences with
      | 0 -> Int.compare b.size a.size
      | c -> c
    end
  | c -> c

let json_fact_stat stat =
  json_assoc
    [
      ("hash", json_string stat.hash);
      ("size", json_int stat.size);
      ("occurrences", json_int stat.occurrences);
      ("repeated_node_cost", json_int (fact_repeated_cost stat));
      ("arity", json_int stat.arity);
      ("max_pre_depth", json_int stat.max_pre_depth);
      ("origins", json_list json_string (StringSet.elements stat.origins));
      ("phases", json_list json_string (StringSet.elements stat.phases));
      ("formula", json_string (truncate_string 240 stat.key));
    ]

let formula_population_json facts =
  let unique_count = List.length facts in
  let total_occurrences = sum_int (List.map (fun f -> f.occurrences) facts) in
  let duplicated_facts = count_if (fun f -> f.occurrences > 1) facts in
  let duplicated_occurrences =
    sum_int (List.map (fun f -> max 0 (f.occurrences - 1)) facts)
  in
  let repeated_node_cost = sum_int (List.map fact_repeated_cost facts) in
  let top =
    facts |> List.sort compare_fact_hotness
    |> fun xs ->
    let rec take n = function
      | _ when n <= 0 -> []
      | [] -> []
      | x :: tl -> x :: take (n - 1) tl
    in
    take 30 xs
  in
  json_assoc
    [
      ("unique_formula_count", json_int unique_count);
      ("formula_occurrences", json_int total_occurrences);
      ("duplicated_formula_count", json_int duplicated_facts);
      ("duplicated_occurrences", json_int duplicated_occurrences);
      ("repeated_node_cost", json_int repeated_node_cost);
      ("max_formula_size", json_int (max_int (List.map (fun f -> f.size) facts)));
      ("max_formula_fanout", json_int (max_int (List.map (fun f -> f.occurrences) facts)));
      ("max_formula_arity", json_int (max_int (List.map (fun f -> f.arity) facts)));
      ("top_repeated_facts", json_list json_fact_stat top);
    ]

let source_node_json (node : Verification_model.node_model) =
  let assumes = node.assumes in
  let guarantees = node.guarantees in
  let transition_body_sizes =
    List.map
      (fun (step : Verification_model.program_step) ->
        sum_int (List.map stmt_size step.body_stmts))
      node.steps
  in
  let ltl_formulas = assumes @ guarantees in
  json_assoc
    [
      ("name", json_string node.node_name);
      ("input_count", json_int (List.length node.inputs));
      ("output_count", json_int (List.length node.outputs));
      ("local_count", json_int (List.length node.locals));
      ("ghost_count", json_int (List.length node.ghosts));
      ("state_count", json_int (List.length node.states));
      ("transition_count", json_int (List.length node.steps));
      ("assume_count", json_int (List.length assumes));
      ("guarantee_count", json_int (List.length guarantees));
      ("state_invariant_count", json_int (List.length node.state_invariants));
      ("total_transition_body_size", json_int (sum_int transition_body_sizes));
      ("max_transition_body_size", json_int (max_int transition_body_sizes));
      ("total_ltl_size", json_int (sum_int (List.map ltl_size ltl_formulas)));
      ("max_ltl_size", json_int (max_int (List.map ltl_size ltl_formulas)));
      ( "max_ltl_temporal_depth",
        json_int (max_int (List.map ltl_temporal_depth ltl_formulas)) );
      ( "max_ltl_pre_depth",
        json_int (max_int (List.map ltl_max_pre_depth ltl_formulas)) );
    ]

let source_json (snapshot : Runtime_snapshot.pipeline_snapshot) =
  let nodes = snapshot.asts.verification_model in
  json_assoc
    [
      ("node_count", json_int (List.length nodes));
      ("nodes", json_list source_node_json nodes);
    ]

let runtime_spec_json (summary : PK.exported_node_summary_ir) =
  let ltl_json ltl =
    json_assoc
      [
        ("size", json_int (ltl_size ltl));
        ("temporal_depth", json_int (ltl_temporal_depth ltl));
        ("pre_depth", json_int (ltl_max_pre_depth ltl));
        ("formula", json_string (truncate_string 360 (string_of_ltl ltl)));
      ]
  in
  json_assoc
    [
      ("assume_count", json_int (List.length summary.assumes));
      ("guarantee_count", json_int (List.length summary.guarantees));
      ("total_assume_size", json_int (sum_int (List.map ltl_size summary.assumes)));
      ("total_guarantee_size", json_int (sum_int (List.map ltl_size summary.guarantees)));
      ("max_guarantee_size", json_int (max_int (List.map ltl_size summary.guarantees)));
      ("assumes", json_list ltl_json summary.assumes);
      ("guarantees", json_list ltl_json summary.guarantees);
    ]

let edge_guard_sizes edges =
  List.map (fun (edge : PK.automaton_edge_ir) -> hexpr_size edge.guard) edges

let automaton_json (automaton : PK.safety_automaton_ir) =
  let guard_sizes = edge_guard_sizes automaton.edges in
  json_assoc
    [
      ("state_count", json_int (List.length automaton.state_labels));
      ("edge_count", json_int (List.length automaton.edges));
      ("bad_state_index", json_opt json_int automaton.bad_state_index);
      ("total_guard_size", json_int (sum_int guard_sizes));
      ("max_guard_size", json_int (max_int guard_sizes));
      ("avg_guard_size", json_float (average_int guard_sizes));
    ]

let count_steps_by_kind steps =
  let safe =
    count_if (fun (step : PK.product_step_ir) -> step.step_kind = StepSafe) steps
  in
  let bad_assumption =
    count_if
      (fun (step : PK.product_step_ir) -> step.step_kind = StepBadAssumption)
      steps
  in
  let bad_guarantee =
    count_if
      (fun (step : PK.product_step_ir) -> step.step_kind = StepBadGuarantee)
      steps
  in
  (safe, bad_assumption, bad_guarantee)

let string_of_product_state (st : PK.product_state_ir) =
  Printf.sprintf "(P=%s,A=%d,G=%d)" st.prog_state st.assume_state_index
    st.guarantee_state_index

let top_counts limit counts =
  counts |> StringMap.bindings
  |> List.sort (fun (_, a) (_, b) -> Int.compare b a)
  |> fun xs ->
  let rec take n = function
    | _ when n <= 0 -> []
    | [] -> []
    | x :: tl -> x :: take (n - 1) tl
  in
  take limit xs

let increment key map =
  let current = Option.value (StringMap.find_opt key map) ~default:0 in
  StringMap.add key (current + 1) map

let product_json (node : PK.node_ir) =
  let steps = node.product_steps in
  let safe, bad_assumption, bad_guarantee = count_steps_by_kind steps in
  let guard_sizes =
    steps
    |> List.map (fun (step : PK.product_step_ir) ->
           hexpr_size step.program_guard + hexpr_size step.assume_edge.guard
           + hexpr_size step.guarantee_edge.guard)
  in
  let by_source =
    List.fold_left
      (fun acc (step : PK.product_step_ir) -> increment (string_of_product_state step.src) acc)
      StringMap.empty steps
  in
  json_assoc
    [
      ("state_count", json_int (List.length node.product_states));
      ("step_count", json_int (List.length steps));
      ("safe_step_count", json_int safe);
      ("bad_assumption_step_count", json_int bad_assumption);
      ("bad_guarantee_step_count", json_int bad_guarantee);
      ("total_step_guard_size", json_int (sum_int guard_sizes));
      ("max_step_guard_size", json_int (max_int guard_sizes));
      ( "top_sources_by_outgoing_steps",
        json_list
          (fun (src, count) ->
            json_assoc [ ("source", json_string src); ("count", json_int count) ])
          (top_counts 20 by_source) );
    ]

let clause_origin_string = function
  | PK.OriginSourceProductSummary -> "source_product_summary"
  | PK.OriginPhaseStepPreSummary -> "phase_step_pre_summary"
  | PK.OriginPhaseStepSummary -> "phase_step_summary"
  | PK.OriginSafety -> "safety"
  | PK.OriginInitNodeInvariant -> "init_node_invariant"
  | PK.OriginInitAutomatonCoherence -> "init_automaton_coherence"
  | PK.OriginPropagationNodeInvariant -> "propagation_node_invariant"
  | PK.OriginPropagationAutomatonCoherence -> "propagation_automaton_coherence"

let phase_string = function
  | PK.CurrentTick -> "current_tick"
  | PK.PreviousTick -> "previous_tick"
  | PK.StepTickContext -> "step_tick_context"

let step_kind_string = function
  | PK.StepSafe -> "safe"
  | PK.StepBadAssumption -> "bad_assumption"
  | PK.StepBadGuarantee -> "bad_guarantee"

let add_rel_fact_formula table ~origin (fact : PK.relational_clause_fact_ir) =
  let phase = phase_string fact.time in
  match fact.desc with
  | PK.RelFactPhaseFormula h | PK.RelFactFormula h ->
      add_fact table ~origin ~phase h
  | PK.RelFactProgramState _ | PK.RelFactGuaranteeState _ | PK.RelFactFalse -> ()

let clause_fact_count (clause : PK.relational_generated_clause_ir) =
  List.length clause.hypotheses + List.length clause.conclusions

let clause_formula_count (clause : PK.relational_generated_clause_ir) =
  let is_formula (fact : PK.relational_clause_fact_ir) =
    match fact.desc with
    | PK.RelFactPhaseFormula _ | PK.RelFactFormula _ -> true
    | PK.RelFactProgramState _ | PK.RelFactGuaranteeState _ | PK.RelFactFalse -> false
  in
  count_if is_formula clause.hypotheses + count_if is_formula clause.conclusions

let clause_json name clauses =
  let fact_counts = List.map clause_fact_count clauses in
  let formula_counts = List.map clause_formula_count clauses in
  let by_origin =
    List.fold_left
      (fun acc (clause : PK.relational_generated_clause_ir) ->
        increment (clause_origin_string clause.origin) acc)
      StringMap.empty clauses
  in
  json_assoc
    [
      ("name", json_string name);
      ("clause_count", json_int (List.length clauses));
      ("total_fact_count", json_int (sum_int fact_counts));
      ("max_fact_count", json_int (max_int fact_counts));
      ("total_formula_fact_count", json_int (sum_int formula_counts));
      ( "by_origin",
        json_list
          (fun (origin, count) ->
            json_assoc [ ("origin", json_string origin); ("count", json_int count) ])
          (StringMap.bindings by_origin) );
    ]

let proof_kernel_json (node : PK.node_ir) =
  let entry_clauses =
    List.concat (List.map (fun (s : PK.proof_step_summary_ir) -> s.entry_clauses) node.proof_step_summaries)
  in
  let post_clauses =
    List.concat (List.map (fun (s : PK.proof_step_summary_ir) -> s.clauses) node.proof_step_summaries)
  in
  json_assoc
    [
      ("summary_count", json_int (List.length node.proof_step_summaries));
      ("symbolic_clause_count", json_int (List.length node.symbolic_generated_clauses));
      ("historical_clause_count", json_int (List.length node.historical_generated_clauses));
      ("eliminated_clause_count", json_int (List.length node.eliminated_generated_clauses));
      ("entry_clauses", clause_json "entry" entry_clauses);
      ("post_clauses", clause_json "post" post_clauses);
    ]

let find_ir_node name nodes =
  List.find_opt (fun (node : Ir.node_ir) -> node.semantics.sem_nname = name) nodes

let canonical_summary_json (summary : Ir.product_step_summary) =
  let formula_sizes formulas =
    List.map (fun (f : Ir.summary_formula) -> hexpr_size f.logic) formulas
  in
  let all_summary_formulas =
    summary.propagation_requires @ summary.requires @ summary.ensures
  in
  let sizes = formula_sizes all_summary_formulas in
  json_assoc
    [
      ("safe_case_count", json_int (List.length summary.safe_cases));
      ("unsafe_case_count", json_int (List.length summary.unsafe_cases));
      ("propagation_requires_count", json_int (List.length summary.propagation_requires));
      ("requires_count", json_int (List.length summary.requires));
      ("ensures_count", json_int (List.length summary.ensures));
      ("total_summary_formula_size", json_int (sum_int sizes));
      ("max_summary_formula_size", json_int (max_int sizes));
    ]

let canonical_summaries_json (node : Ir.node_ir option) =
  match node with
  | None -> json_assoc [ ("available", json_bool false) ]
  | Some node ->
      let summaries = node.summaries in
      let safe_cases =
        sum_int (List.map (fun (s : Ir.product_step_summary) -> List.length s.safe_cases) summaries)
      in
      let unsafe_cases =
        sum_int (List.map (fun (s : Ir.product_step_summary) -> List.length s.unsafe_cases) summaries)
      in
      let propagation_requires =
        sum_int
          (List.map
             (fun (s : Ir.product_step_summary) -> List.length s.propagation_requires)
             summaries)
      in
      let requires =
        sum_int (List.map (fun (s : Ir.product_step_summary) -> List.length s.requires) summaries)
      in
      let ensures =
        sum_int (List.map (fun (s : Ir.product_step_summary) -> List.length s.ensures) summaries)
      in
      let summary_jsons = List.map canonical_summary_json summaries in
      json_assoc
        [
          ("available", json_bool true);
          ("summary_count", json_int (List.length summaries));
          ("safe_case_count", json_int safe_cases);
          ("unsafe_case_count", json_int unsafe_cases);
          ("propagation_requires_count", json_int propagation_requires);
          ("requires_count", json_int requires);
          ("ensures_count", json_int ensures);
          ("summaries", `List summary_jsons);
        ]

let origin_for_node node_name suffix = node_name ^ "." ^ suffix

let collect_summary_facts table (node : Ir.node_ir) =
  let node_name = node.semantics.sem_nname in
  let add_summary_formula origin phase (f : Ir.summary_formula) =
    add_fact table ~origin:(origin_for_node node_name origin) ~phase f.logic
  in
  List.iter
    (fun (summary : Ir.product_step_summary) ->
      List.iter
        (add_summary_formula "canonical.propagation_requires" "previous_tick")
        summary.propagation_requires;
      List.iter (add_summary_formula "canonical.requires" "step_tick_context") summary.requires;
      List.iter (add_summary_formula "canonical.ensures" "current_tick") summary.ensures;
      List.iter
        (fun (case : Ir.safe_product_case) ->
          add_summary_formula "canonical.safe_case.admissible_guard" "step_tick_context"
            case.admissible_guard)
        summary.safe_cases;
      List.iter
        (fun (case : Ir.unsafe_product_case) ->
          add_summary_formula "canonical.unsafe_case.excluded_guard" "step_tick_context"
            case.excluded_guard)
        summary.unsafe_cases)
    node.summaries;
  List.iter
    (add_summary_formula "canonical.init_invariant_goal" "current_tick")
    node.init_invariant_goals

let collect_kernel_facts table ~node_name (node : PK.node_ir) =
  let origin suffix = origin_for_node node_name suffix in
  List.iter
    (fun (edge : PK.automaton_edge_ir) ->
      add_fact table ~origin:(origin "kernel.assume_automaton.edge_guard")
        ~phase:"step_tick_context" edge.guard)
    node.assume_automaton.edges;
  List.iter
    (fun (edge : PK.automaton_edge_ir) ->
      add_fact table ~origin:(origin "kernel.guarantee_automaton.edge_guard")
        ~phase:"step_tick_context" edge.guard)
    node.guarantee_automaton.edges;
  List.iter
    (fun (step : PK.product_step_ir) ->
      add_fact table ~origin:(origin "kernel.product.program_guard") ~phase:"step_tick_context"
        step.program_guard;
      add_fact table ~origin:(origin "kernel.product.assume_guard") ~phase:"step_tick_context"
        step.assume_edge.guard;
      add_fact table ~origin:(origin "kernel.product.guarantee_guard") ~phase:"step_tick_context"
        step.guarantee_edge.guard)
    node.product_steps;
  List.iter
    (fun (summary : PK.proof_step_summary_ir) ->
      List.iter
        (fun (clause : PK.relational_generated_clause_ir) ->
          let origin = origin ("kernel.entry_clause." ^ clause_origin_string clause.origin) in
          List.iter (add_rel_fact_formula table ~origin) clause.hypotheses;
          List.iter (add_rel_fact_formula table ~origin) clause.conclusions)
        summary.entry_clauses;
      List.iter
        (fun (clause : PK.relational_generated_clause_ir) ->
          let origin = origin ("kernel.post_clause." ^ clause_origin_string clause.origin) in
          List.iter (add_rel_fact_formula table ~origin) clause.hypotheses;
          List.iter (add_rel_fact_formula table ~origin) clause.conclusions)
        summary.clauses)
    node.proof_step_summaries

let collect_source_ltl_facts table (node : Verification_model.node_model) =
  let origin suffix = origin_for_node node.node_name suffix in
  let rec go origin phase = function
    | LTrue | LFalse -> ()
    | LAtom (a, _, b) ->
        add_fact table ~origin ~phase a;
        add_fact table ~origin ~phase b
    | LNot a | LX a | LG a -> go origin phase a
    | LAnd (a, b) | LOr (a, b) | LImp (a, b) | LW (a, b) ->
        go origin phase a;
        go origin phase b
  in
  List.iter (go (origin "source.assume.atom") "source_ltl") node.assumes;
  List.iter (go (origin "source.guarantee.atom") "source_ltl") node.guarantees;
  List.iter
    (fun (inv : Verification_model.state_invariant) ->
      add_fact table ~origin:(origin "source.state_invariant") ~phase:"source_fo"
        inv.formula)
    node.state_invariants

let source_node_of_runtime_name runtime_name source_nodes =
  let is_runtime_split source_name =
    runtime_name = source_name
    || starts_with ~prefix:(source_name ^ "__kairos_") runtime_name
  in
  List.find_opt
    (fun (n : Verification_model.node_model) -> is_runtime_split n.node_name)
    source_nodes

let node_report_json snapshot (summary : PK.exported_node_summary_ir) =
  let node = summary.normalized_ir in
  let canonical_node =
    find_ir_node summary.signature.node_name snapshot.Runtime_snapshot.asts.instrumentation
  in
  let source_node =
    source_node_of_runtime_name summary.signature.node_name
      snapshot.Runtime_snapshot.asts.verification_model
  in
  json_assoc
    [
      ("name", json_string summary.signature.node_name);
      ("runtime_spec", runtime_spec_json summary);
      ("assume_automaton", automaton_json node.assume_automaton);
      ("guarantee_automaton", automaton_json node.guarantee_automaton);
      ("product", product_json node);
      ("canonical_summaries", canonical_summaries_json canonical_node);
      ("proof_kernel", proof_kernel_json node);
      ( "source",
        match source_node with
        | None -> json_assoc [ ("available", json_bool false) ]
        | Some node -> source_node_json node );
    ]

let collect_all_facts snapshot artifacts =
  let table = Hashtbl.create 4096 in
  List.iter (collect_source_ltl_facts table) snapshot.Runtime_snapshot.asts.verification_model;
  List.iter (collect_summary_facts table) snapshot.Runtime_snapshot.asts.instrumentation;
  List.iter
    (fun (summary : PK.exported_node_summary_ir) ->
      collect_kernel_facts table ~node_name:summary.signature.node_name
        summary.normalized_ir)
    artifacts.Pipeline_artifact_bundle.exported_node_summaries;
  fact_stats table

let line_count text =
  let len = String.length text in
  if len = 0 then 0
  else
    let newlines = ref 0 in
    String.iter (fun c -> if c = '\n' then incr newlines) text;
    if text.[len - 1] = '\n' then !newlines else !newlines + 1

let count_lines pred text =
  text |> String.split_on_char '\n'
  |> List.fold_left
       (fun acc line ->
         let line = String.trim line in
         if pred line then acc + 1 else acc)
       0

let why3_json why_text ~why_text_s =
  let lines = String.split_on_char '\n' why_text in
  let shared_predicate_count =
    count_lines (starts_with ~prefix:"predicate shared_contract_formula_") why_text
  in
  let step_helper_count =
    count_lines
      (fun line ->
        starts_with ~prefix:"let step_" line
        || starts_with ~prefix:"let ghost step_" line)
      why_text
  in
  let logic_decl_count =
    count_lines
      (fun line ->
        starts_with ~prefix:"predicate " line
        || starts_with ~prefix:"function " line
        || starts_with ~prefix:"val " line)
      why_text
  in
  let assert_count =
    count_lines (starts_with ~prefix:"assert") why_text
  in
  let shared_contract_assert_count =
    count_lines
      (fun line ->
        starts_with ~prefix:"assert" line
        && contains_substring line "shared_contract_formula_")
      why_text
  in
  let max_line_length =
    max_int (List.map String.length lines)
  in
  json_assoc
    [
      ("generated", json_bool true);
      ("generation_wall_s", json_float why_text_s);
      ("byte_count", json_int (String.length why_text));
      ("line_count", json_int (line_count why_text));
      ("max_line_length", json_int max_line_length);
      ("logic_declaration_count", json_int logic_decl_count);
      ("shared_predicate_count", json_int shared_predicate_count);
      ("step_helper_count", json_int step_helper_count);
      ("requires_count", json_int (count_lines (starts_with ~prefix:"requires") why_text));
      ("ensures_count", json_int (count_lines (starts_with ~prefix:"ensures") why_text));
      ("assert_count", json_int assert_count);
      ("shared_contract_assert_count", json_int shared_contract_assert_count);
    ]

let flow_meta_json snapshot =
  Pipeline_outputs.flow_meta
    ~proof_encoding:snapshot.Runtime_snapshot.proof_encoding
    ~proof_optimizations:snapshot.Runtime_snapshot.proof_optimizations
    snapshot.Runtime_snapshot.infos
  |> json_list (fun (section, fields) ->
         json_assoc
           [
             ("section", json_string section);
             ( "fields",
               json_assoc (List.map (fun (k, v) -> (k, json_string v)) fields) );
           ])

let proof_optimizations_json (opts : Pipeline_types.proof_optimizations) =
  json_assoc
    [
      ("group_public_non_w_guarantees", json_bool opts.group_public_non_w_guarantees);
      ("share_why3_facts", json_bool opts.share_why3_facts);
      ("simplify_why3_formulas", json_bool opts.simplify_why3_formulas);
      ("slice_why3_transition_bodies", json_bool opts.slice_why3_transition_bodies);
      ("simplify_why3_runtime_actions", json_bool opts.simplify_why3_runtime_actions);
      ("deduplicate_why3_terms", json_bool opts.deduplicate_why3_terms);
      ("group_why3_product_steps", json_bool opts.group_why3_product_steps);
      ( "why3_product_step_group_max_cost",
        json_int opts.why3_product_step_group_max_cost );
    ]

let proof_encoding_json (encoding : Pipeline_types.proof_encoding) =
  json_string (Pipeline_types.string_of_proof_encoding encoding)

let render_json ~input_file ~artifact_build_s ~why_text_s ~snapshot ~artifacts ~why_text =
  let facts = collect_all_facts snapshot artifacts in
  let nodes =
    List.map (node_report_json snapshot) artifacts.Pipeline_artifact_bundle.exported_node_summaries
  in
  let root =
    json_assoc
      [
        ("format", json_string "kairos-cost-report-v1");
        ("input_file", json_string input_file);
        ("proof_encoding", proof_encoding_json snapshot.proof_encoding);
        ( "timings",
          json_assoc
            [
              ("artifact_build_s", json_float artifact_build_s);
              ("why_text_generation_s", json_float why_text_s);
            ] );
        ("proof_optimizations", proof_optimizations_json snapshot.proof_optimizations);
        ("flow_meta", flow_meta_json snapshot);
        ("source", source_json snapshot);
        ("nodes", `List nodes);
        ("formula_population", formula_population_json facts);
        ("why3", why3_json why_text ~why_text_s);
        ( "notes",
          json_list json_string
            [
              "This report is observational and does not change proof obligations.";
              "Formula hashes are based on the current pretty-printed FO syntax.";
              "Why3 metrics are computed on generated WhyML text before VC/SMT solving.";
            ] );
      ]
  in
  Json.pretty_to_string root ^ "\n"
