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
