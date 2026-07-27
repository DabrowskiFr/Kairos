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

(** Aggregated VC taxonomy fields for concrete engine metadata. *)

let fmt_s = Engine_timing_fields.fmt_s
let sanitize_csv_value = Engine_timing_fields.sanitize_csv_value

type vc_taxonomy_acc = {
  mutable goal_count : int;
  mutable valid_count : int;
  mutable invalid_count : int;
  mutable timeout_count : int;
  mutable unknown_count : int;
  mutable failure_count : int;
  mutable pending_count : int;
  mutable prepare_s : float;
  mutable print_s : float;
  mutable spawn_s : float;
  mutable wait_s : float;
  mutable solver_s : float;
  mutable sample_goal : string;
}

let empty_vc_taxonomy_acc sample_goal =
  {
    goal_count = 0;
    valid_count = 0;
    invalid_count = 0;
    timeout_count = 0;
    unknown_count = 0;
    failure_count = 0;
    pending_count = 0;
    prepare_s = 0.0;
    print_s = 0.0;
    spawn_s = 0.0;
    wait_s = 0.0;
    solver_s = 0.0;
    sample_goal;
  }

let opt_value = function Some value -> value | None -> ""

let add_trace_to_vc_taxonomy acc (trace : Pipeline_types.proof_trace) =
  acc.goal_count <- acc.goal_count + 1;
  begin
    match String.lowercase_ascii trace.status with
    | "valid" | "proved" -> acc.valid_count <- acc.valid_count + 1
    | "invalid" -> acc.invalid_count <- acc.invalid_count + 1
    | "timeout" -> acc.timeout_count <- acc.timeout_count + 1
    | "unknown" -> acc.unknown_count <- acc.unknown_count + 1
    | "pending" -> acc.pending_count <- acc.pending_count + 1
    | _ -> acc.failure_count <- acc.failure_count + 1
  end;
  acc.prepare_s <- acc.prepare_s +. trace.why3_prepare_s;
  acc.print_s <- acc.print_s +. trace.why3_print_s;
  acc.spawn_s <- acc.spawn_s +. trace.why3_spawn_s;
  acc.wait_s <- acc.wait_s +. trace.why3_wait_s;
  acc.solver_s <- acc.solver_s +. trace.why3_solver_s

let grouped_vc_taxonomy traces key_of_trace =
  let table = Hashtbl.create 64 in
  List.iter
    (fun (trace : Pipeline_types.proof_trace) ->
      let key = key_of_trace trace in
      let acc =
        match Hashtbl.find_opt table key with
        | Some acc -> acc
        | None ->
            let acc = empty_vc_taxonomy_acc trace.goal_name in
            Hashtbl.add table key acc;
            acc
      in
      add_trace_to_vc_taxonomy acc trace)
    traces;
  Hashtbl.to_seq table |> List.of_seq
  |> List.sort (fun (_key_a, acc_a) (_key_b, acc_b) ->
         match Int.compare acc_b.goal_count acc_a.goal_count with
         | 0 -> Float.compare acc_b.prepare_s acc_a.prepare_s
         | cmp -> cmp)

let vc_taxonomy_summary_fields ~prefix ~rank labels acc =
  let row_prefix = Printf.sprintf "%s_%03d_" prefix rank in
  let label_fields =
    labels
    |> List.map (fun (name, value) ->
           (row_prefix ^ name, sanitize_csv_value value))
  in
  label_fields
  @ [
      (row_prefix ^ "goal_count", string_of_int acc.goal_count);
      (row_prefix ^ "valid_count", string_of_int acc.valid_count);
      (row_prefix ^ "invalid_count", string_of_int acc.invalid_count);
      (row_prefix ^ "timeout_count", string_of_int acc.timeout_count);
      (row_prefix ^ "unknown_count", string_of_int acc.unknown_count);
      (row_prefix ^ "failure_count", string_of_int acc.failure_count);
      (row_prefix ^ "pending_count", string_of_int acc.pending_count);
      (row_prefix ^ "prepare_s", fmt_s acc.prepare_s);
      (row_prefix ^ "print_s", fmt_s acc.print_s);
      (row_prefix ^ "spawn_s", fmt_s acc.spawn_s);
      (row_prefix ^ "wait_s", fmt_s acc.wait_s);
      (row_prefix ^ "solver_s", fmt_s acc.solver_s);
      (row_prefix ^ "sample_goal", sanitize_csv_value acc.sample_goal);
    ]

let fields (traces : Pipeline_types.proof_trace list) =
  let family_groups =
    grouped_vc_taxonomy traces (fun trace ->
        ( trace.obligation_kind,
          opt_value trace.obligation_family,
          opt_value trace.obligation_category ))
    |> List.mapi (fun idx ((kind, family, category), acc) ->
           vc_taxonomy_summary_fields ~prefix:"vc_taxonomy_family"
             ~rank:(idx + 1)
             [ ("kind", kind); ("family", family); ("category", category) ]
             acc)
    |> List.concat
  in
  let transition_groups =
    grouped_vc_taxonomy traces (fun trace ->
        ( trace.obligation_kind,
          opt_value trace.node,
          opt_value trace.transition,
          opt_value trace.obligation_category ))
    |> List.mapi (fun idx ((kind, node, transition, category), acc) ->
           vc_taxonomy_summary_fields ~prefix:"vc_taxonomy_transition"
             ~rank:(idx + 1)
             [
               ("kind", kind);
               ("node", node);
               ("transition", transition);
               ("category", category);
             ]
             acc)
    |> List.concat
  in
  let source_groups =
    grouped_vc_taxonomy traces (fun trace ->
        ( trace.obligation_kind,
          opt_value trace.node,
          opt_value trace.transition,
          trace.source ))
    |> List.mapi (fun idx ((kind, node, transition, source), acc) ->
           vc_taxonomy_summary_fields ~prefix:"vc_taxonomy_source"
             ~rank:(idx + 1)
             [
               ("kind", kind);
               ("node", node);
               ("transition", transition);
               ("source", source);
             ]
             acc)
    |> List.concat
  in
  [
    ("vc_taxonomy_goal_count", string_of_int (List.length traces));
    ( "vc_taxonomy_family_group_count",
      string_of_int
        (List.length
           (grouped_vc_taxonomy traces (fun trace ->
                ( trace.obligation_kind,
                  opt_value trace.obligation_family,
                  opt_value trace.obligation_category ))) ));
    ( "vc_taxonomy_transition_group_count",
      string_of_int
        (List.length
           (grouped_vc_taxonomy traces (fun trace ->
                ( trace.obligation_kind,
                  opt_value trace.node,
                  opt_value trace.transition,
                  opt_value trace.obligation_category ))) ));
    ( "vc_taxonomy_source_group_count",
      string_of_int
        (List.length
           (grouped_vc_taxonomy traces (fun trace ->
                ( trace.obligation_kind,
                  opt_value trace.node,
                  opt_value trace.transition,
                  trace.source ))) ));
  ]
  @ family_groups @ transition_groups @ source_groups
