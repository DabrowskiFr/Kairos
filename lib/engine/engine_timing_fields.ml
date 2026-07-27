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

(** Formatting helpers for concrete engine timing metadata. *)

let fmt_s x = Printf.sprintf "%.6f" x

let bool_s = function true -> "true" | false -> "false"

let sanitize_csv_value value =
  String.map
    (function
      | ',' | '\n' | '\r' -> ';'
      | '"' -> '\''
      | c -> c)
    value

let solver_sum_s (goals : Pipeline_types.goal_info list) : float =
  List.fold_left (fun acc (_, _, time_s, _, _) -> acc +. time_s) 0.0 goals

let goal_status_is_pending (_, status, _, _, _) =
  String.lowercase_ascii status = "pending"

let why3_worker_timing_fields
    (worker : External_timing.why3_worker_snapshot) =
  let prefix = Printf.sprintf "why3_worker_%d_" worker.worker_id in
  [
    (prefix ^ "input_goal_count", string_of_int worker.worker_input_goal_count);
    (prefix ^ "prover_goal_count", string_of_int worker.worker_prover_goal_count);
    ( prefix ^ "duplicate_goal_count",
      string_of_int worker.worker_duplicate_goal_count );
    (prefix ^ "fallback_count", string_of_int worker.worker_fallback_count);
    (prefix ^ "wall_s", fmt_s worker.worker_wall_s);
    (prefix ^ "prepare_s", fmt_s worker.worker_prepare_s);
    (prefix ^ "print_s", fmt_s worker.worker_print_s);
    (prefix ^ "spawn_s", fmt_s worker.worker_spawn_s);
    (prefix ^ "wait_s", fmt_s worker.worker_wait_s);
    (prefix ^ "solver_s", fmt_s worker.worker_solver_s);
    (prefix ^ "last_goal", worker.worker_last_goal);
  ]

let ir_size_count (name : string) (size : External_timing.ir_size_metrics) :
    int =
  match name with
  | "node_count" -> size.node_count
  | "summary_count" -> size.summary_count
  | "safe_case_count" -> size.safe_case_count
  | "unsafe_case_count" -> size.unsafe_case_count
  | "propagation_requires_count" -> size.propagation_requires_count
  | "requires_count" -> size.requires_count
  | "ensures_count" -> size.ensures_count
  | "elaboration_checks_count" -> size.elaboration_checks_count
  | "init_invariant_goal_count" -> size.init_invariant_goal_count
  | "formula_occurrence_count" -> size.formula_occurrence_count
  | "unique_formula_count" -> size.unique_formula_count
  | "duplicated_formula_occurrence_count" ->
      size.formula_occurrence_count - size.unique_formula_count
  | _ -> invalid_arg ("unknown IR size metric: " ^ name)

let ir_pass_size_fields (pass : External_timing.ir_pass_snapshot) =
  let prefix = "ir_" ^ pass.pass_name ^ "_" in
  [
    "node_count";
    "summary_count";
    "safe_case_count";
    "unsafe_case_count";
    "propagation_requires_count";
    "requires_count";
    "ensures_count";
    "elaboration_checks_count";
    "init_invariant_goal_count";
    "formula_occurrence_count";
    "unique_formula_count";
    "duplicated_formula_occurrence_count";
  ]
  |> List.concat_map (fun metric ->
         let before = ir_size_count metric pass.before in
         let after_ = ir_size_count metric pass.after_ in
         [
           (prefix ^ "before_" ^ metric, string_of_int before);
           (prefix ^ "after_" ^ metric, string_of_int after_);
           (prefix ^ "delta_" ^ metric, string_of_int (after_ - before));
         ])

let ir_fact_family_fields
    (family : External_timing.ir_fact_family_snapshot) =
  let prefix =
    "ir_family_" ^ family.pass_name ^ "_" ^ family.family_name ^ "_"
  in
  [
    ("candidate_count", family.candidate_count);
    ("inserted_count", family.inserted_count);
    ("unique_candidate_count", family.unique_candidate_count);
    ("unique_inserted_count", family.unique_inserted_count);
    ( "duplicate_candidate_count",
      family.candidate_count - family.unique_candidate_count );
    ( "duplicate_inserted_count",
      family.inserted_count - family.unique_inserted_count );
  ]
  |> List.map (fun (name, count) -> (prefix ^ name, string_of_int count))

let product_group_fields
    (groups : External_timing.why3_product_group_snapshot list) =
  let emitted_as_group
      (group : External_timing.why3_product_group_snapshot) =
    group.emitted_as_group
  in
  let split_due_to_cost
      (group : External_timing.why3_product_group_snapshot) =
    group.split_due_to_cost
  in
  let group_name (group : External_timing.why3_product_group_snapshot) =
    group.group_name
  in
  let node_name (group : External_timing.why3_product_group_snapshot) =
    group.node_name
  in
  let transition_id
      (group : External_timing.why3_product_group_snapshot) =
    group.transition_id
  in
  let step_class (group : External_timing.why3_product_group_snapshot) =
    group.step_class
  in
  let source_state (group : External_timing.why3_product_group_snapshot) =
    group.source_state
  in
  let edge_count (group : External_timing.why3_product_group_snapshot) =
    group.edge_count
  in
  let distinct_pre_count
      (group : External_timing.why3_product_group_snapshot) =
    group.distinct_pre_count
  in
  let distinct_post_count
      (group : External_timing.why3_product_group_snapshot) =
    group.distinct_post_count
  in
  let post_implication_count
      (group : External_timing.why3_product_group_snapshot) =
    group.post_implication_count
  in
  let pre_text_bytes
      (group : External_timing.why3_product_group_snapshot) =
    group.pre_text_bytes
  in
  let post_text_bytes
      (group : External_timing.why3_product_group_snapshot) =
    group.post_text_bytes
  in
  let estimated_cost
      (group : External_timing.why3_product_group_snapshot) =
    group.estimated_cost
  in
  let factor_kind (group : External_timing.why3_product_group_snapshot) =
    group.factor_kind
  in
  let factor_original_estimated_cost
      (group : External_timing.why3_product_group_snapshot) =
    group.factor_original_estimated_cost
  in
  let factor_post_common_estimated_cost
      (group : External_timing.why3_product_group_snapshot) =
    group.factor_post_common_estimated_cost
  in
  let factor_pre_common_estimated_cost
      (group : External_timing.why3_product_group_snapshot) =
    group.factor_pre_common_estimated_cost
  in
  let factor_pre_and_post_common_estimated_cost
      (group : External_timing.why3_product_group_snapshot) =
    group.factor_pre_and_post_common_estimated_cost
  in
  let max_cost (group : External_timing.why3_product_group_snapshot) =
    group.max_cost
  in
  let sum_by f = List.fold_left (fun acc group -> acc + f group) 0 groups in
  let max_by f = List.fold_left (fun acc group -> max acc (f group)) 0 groups in
  let count_factor kind =
    List.fold_left
      (fun acc group -> if factor_kind group = kind then acc + 1 else acc)
      0 groups
  in
  let emitted_group_count =
    List.fold_left
      (fun acc group -> if emitted_as_group group then acc + 1 else acc)
      0 groups
  in
  let split_group_count =
    List.fold_left
      (fun acc group -> if split_due_to_cost group then acc + 1 else acc)
      0 groups
  in
  let top_groups =
    groups
    |> List.sort (fun left right ->
           match Int.compare (estimated_cost right) (estimated_cost left) with
           | 0 -> Int.compare (edge_count right) (edge_count left)
           | cmp -> cmp)
    |> List.filteri (fun index _ -> index < 20)
    |> List.mapi (fun index group ->
           let prefix =
             Printf.sprintf "why3_product_group_top_%03d_" (index + 1)
           in
           [
             (prefix ^ "name", sanitize_csv_value (group_name group));
             (prefix ^ "node", sanitize_csv_value (node_name group));
             (prefix ^ "transition", sanitize_csv_value (transition_id group));
             (prefix ^ "step_class", sanitize_csv_value (step_class group));
             (prefix ^ "source_state", sanitize_csv_value (source_state group));
             (prefix ^ "emitted_as_group", bool_s (emitted_as_group group));
             (prefix ^ "split_due_to_cost", bool_s (split_due_to_cost group));
             (prefix ^ "edge_count", string_of_int (edge_count group));
             ( prefix ^ "distinct_pre_count",
               string_of_int (distinct_pre_count group) );
             ( prefix ^ "distinct_post_count",
               string_of_int (distinct_post_count group) );
             ( prefix ^ "post_implication_count",
               string_of_int (post_implication_count group) );
             (prefix ^ "pre_text_bytes", string_of_int (pre_text_bytes group));
             ( prefix ^ "post_text_bytes",
               string_of_int (post_text_bytes group) );
             (prefix ^ "estimated_cost", string_of_int (estimated_cost group));
             (prefix ^ "factor_kind", sanitize_csv_value (factor_kind group));
             ( prefix ^ "factor_original_estimated_cost",
               string_of_int (factor_original_estimated_cost group) );
             ( prefix ^ "factor_post_common_estimated_cost",
               string_of_int (factor_post_common_estimated_cost group) );
             ( prefix ^ "factor_pre_common_estimated_cost",
               string_of_int (factor_pre_common_estimated_cost group) );
             ( prefix ^ "factor_pre_and_post_common_estimated_cost",
               string_of_int
                 (factor_pre_and_post_common_estimated_cost group) );
             (prefix ^ "max_cost", string_of_int (max_cost group));
           ])
    |> List.concat
  in
  [
    ("why3_product_group_count", string_of_int (List.length groups));
    ("why3_product_group_emitted_count", string_of_int emitted_group_count);
    ("why3_product_group_split_count", string_of_int split_group_count);
    ("why3_product_group_edge_count", string_of_int (sum_by edge_count));
    ( "why3_product_group_max_edge_count",
      string_of_int (max_by edge_count) );
    ( "why3_product_group_max_distinct_pre_count",
      string_of_int (max_by distinct_pre_count) );
    ( "why3_product_group_max_distinct_post_count",
      string_of_int (max_by distinct_post_count) );
    ( "why3_product_group_max_post_implication_count",
      string_of_int (max_by post_implication_count) );
    ( "why3_product_group_max_pre_text_bytes",
      string_of_int (max_by pre_text_bytes) );
    ( "why3_product_group_max_post_text_bytes",
      string_of_int (max_by post_text_bytes) );
    ( "why3_product_group_max_estimated_cost",
      string_of_int (max_by estimated_cost) );
    ( "why3_product_group_total_estimated_cost",
      string_of_int (sum_by estimated_cost) );
    ( "why3_product_group_factor_original_count",
      string_of_int (count_factor "original") );
    ( "why3_product_group_factor_post_common_count",
      string_of_int (count_factor "post_common") );
    ( "why3_product_group_factor_pre_common_count",
      string_of_int (count_factor "pre_common") );
    ( "why3_product_group_factor_pre_and_post_common_count",
      string_of_int (count_factor "pre_and_post_common") );
    ( "why3_product_group_factor_original_total_estimated_cost",
      string_of_int (sum_by factor_original_estimated_cost) );
    ( "why3_product_group_factor_post_common_total_estimated_cost",
      string_of_int (sum_by factor_post_common_estimated_cost) );
    ( "why3_product_group_factor_pre_common_total_estimated_cost",
      string_of_int (sum_by factor_pre_common_estimated_cost) );
    ( "why3_product_group_factor_pre_and_post_common_total_estimated_cost",
      string_of_int (sum_by factor_pre_and_post_common_estimated_cost) );
  ]
  @ top_groups

let sanitize_field_suffix value =
  String.map
    (function
      | 'a' .. 'z' as c -> c
      | 'A' .. 'Z' as c -> Char.lowercase_ascii c
      | '0' .. '9' as c -> c
      | _ -> '_')
    value

let product_individual_reason_fields
    (reasons :
      External_timing.why3_product_individual_reason_snapshot list) =
  let add_count reason count counts =
    let rec loop acc = function
      | [] -> List.rev ((reason, count) :: acc)
      | (known_reason, known_count) :: rest when known_reason = reason ->
          List.rev_append acc ((known_reason, known_count + count) :: rest)
      | item :: rest -> loop (item :: acc) rest
    in
    loop [] counts
  in
  let reason_counts =
    reasons
    |> List.fold_left
         (fun acc
              (item :
                External_timing.why3_product_individual_reason_snapshot)
            -> add_count item.reason item.count acc)
         []
    |> List.sort (fun (left, _) (right, _) -> String.compare left right)
  in
  let total =
    List.fold_left (fun acc (_reason, count) -> acc + count) 0 reason_counts
  in
  ("why3_product_individual_count", string_of_int total)
  :: List.map
       (fun (reason, count) ->
         ( "why3_product_individual_reason_"
           ^ sanitize_field_suffix reason ^ "_count",
           string_of_int count ))
       reason_counts
