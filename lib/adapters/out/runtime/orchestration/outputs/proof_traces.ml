(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frederic Dabrowski
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

module Goal_results = Proof_goal_results
module Contract = Kairos_why3_contract.Why3_contract

let needed (cfg : Pipeline_config.config) : bool =
  cfg.collect_ir_metrics || cfg.compute_proof_diagnostics
  || cfg.generate_vc_text || cfg.generate_smt_text
  || Option.is_some cfg.proof_progress_path

let diagnostic_for_goal ~goal_name ~status ~native_probe =
  let diagnostic =
    Proof_trace_diagnostics.build ~status ~goal_text:goal_name ~native_probe
  in
  (diagnostic, native_probe)

let base_trace ~idx ~goal_name ~status ~time_s
    ~(timing : Contract.goal_timing) ~solver_status ~vc_id ~vc_span
    ~smt_span ~dump_path ~diagnostic =
  {
    Pipeline_proof_types.goal_index = idx;
    stable_id = Printf.sprintf "vc-%03d" (idx + 1);
    goal_name;
    status;
    solver_status;
    time_s;
    why3_prepare_s = timing.prepare_s;
    why3_print_s = timing.print_s;
    why3_spawn_s = timing.spawn_s;
    why3_wait_s = timing.wait_s;
    why3_solver_s = timing.solver_s;
    source = "";
    node = None;
    transition = None;
    obligation_kind = "unknown";
    obligation_family = None;
    obligation_category = None;
    vc_id;
    source_span = None;
    why_span = None;
    vc_span;
    smt_span;
    dump_path;
    diagnostic;
  }

let goal_name_lookup_key (goal_name : string) =
  match String.index_opt goal_name '\'' with
  | None -> goal_name
  | Some index -> String.sub goal_name 0 index

let manifest_index (manifest : Why_pipeline.compilation_manifest) =
  let index = Hashtbl.create (List.length manifest * 2 + 1) in
  List.iter
    (fun (entry : Why_compile.compiled_obligation) ->
      Hashtbl.replace index entry.generated_symbol entry)
    manifest;
  index

let apply_manifest manifest goal_name
    (trace : Pipeline_proof_types.proof_trace) =
  match Hashtbl.find_opt manifest (goal_name_lookup_key goal_name) with
  | None -> trace
  | Some (entry : Why_compile.compiled_obligation) ->
      {
        trace with
        source = entry.source;
        node = Some entry.node_name;
        transition = Some entry.transition;
        obligation_kind = entry.obligation_kind;
        obligation_family = Some entry.obligation_family;
        obligation_category = entry.obligation_category;
      }

let build_from_execution ~goals ~manifest
    ~(goal_results : Proof_goal_results.t list)
    ~(vc_ids_ordered : int list)
    ~(vc_spans_ordered : Pipeline_proof_types.text_span list)
    ~(smt_spans_ordered : Pipeline_proof_types.text_span list) :
    Pipeline_proof_types.proof_trace list =
  let manifest = manifest_index manifest in
  let goal_result_tbl = Hashtbl.create (List.length goal_results * 2 + 1) in
  List.iter
    (fun goal_result ->
      Hashtbl.replace goal_result_tbl
        goal_result.Goal_results.result_index goal_result)
    goal_results;
  goals
  |> List.filter_map (fun (goal : Contract.goal_descriptor) ->
         let idx = goal.goal_index in
         let goal_result =
           match Hashtbl.find_opt goal_result_tbl idx with
           | Some goal -> goal
           | None ->
               Goal_results.pending ~index:idx ~goal_name:goal.goal_name
                 ~vcid:(Some (string_of_int (List.nth vc_ids_ordered idx)))
         in
         let goal_name = goal_result.Goal_results.result_goal_name in
         let status = goal_result.Goal_results.result_status in
         let diagnostic, native_probe =
           diagnostic_for_goal ~goal_name ~status
             ~native_probe:goal_result.Goal_results.result_probe
         in
         let solver_status =
           match native_probe with Some probe -> probe.status | None -> status
         in
         let trace =
           base_trace ~idx ~goal_name ~status
             ~time_s:goal_result.Goal_results.result_time_s
             ~timing:goal_result.Goal_results.result_timing ~solver_status
             ~vc_id:goal_result.Goal_results.result_vcid
             ~vc_span:(List.nth_opt vc_spans_ordered idx)
             ~smt_span:(List.nth_opt smt_spans_ordered idx)
             ~dump_path:goal_result.Goal_results.result_dump_path
             ~diagnostic
         in
         Some (apply_manifest manifest goal_name trace))

let build_fast ~manifest (goal_results : Proof_goal_results.t list) :
    Pipeline_proof_types.proof_trace list =
  let manifest = manifest_index manifest in
  goal_results
  |> List.map (fun goal_result ->
         let idx = goal_result.Goal_results.result_index in
         let goal_name = goal_result.Goal_results.result_goal_name in
         let status = goal_result.Goal_results.result_status in
         let diagnostic =
           Proof_trace_diagnostics.build ~status ~goal_text:goal_name
             ~native_probe:None
         in
         let trace =
           base_trace ~idx ~goal_name ~status
             ~time_s:goal_result.Goal_results.result_time_s
             ~timing:goal_result.Goal_results.result_timing
             ~solver_status:status
             ~vc_id:goal_result.Goal_results.result_vcid ~vc_span:None
             ~smt_span:None
             ~dump_path:goal_result.Goal_results.result_dump_path
             ~diagnostic
         in
         apply_manifest manifest goal_name trace)

let goals_of_proof_traces (proof_traces : Pipeline_proof_types.proof_trace list) :
    Pipeline_proof_types.goal_info list =
  List.map
    (fun (trace : Pipeline_proof_types.proof_trace) ->
      (trace.goal_name, trace.status, trace.time_s, trace.dump_path, trace.vc_id))
    proof_traces

let goals_of_goal_results (goal_results : Proof_goal_results.t list) :
    Pipeline_proof_types.goal_info list =
  List.map Proof_goal_results.to_goal_info goal_results
