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

include Pipeline_outputs_helpers

let build_outputs ~(cfg : Pipeline_types.config) ~(asts : Pipeline_types.ast_stages)
    ~(infos : Pipeline_types.stage_infos) :
    (Pipeline_types.outputs, Pipeline_types.error) result =
  match Pipeline_artifact_bundle.build ~asts with
  | Error msg -> Error (Pipeline_types.Stage_error msg)
  | Ok artifacts ->
  try
    let obligation_summary = Obligation_taxonomy.summarize_program asts.instrumentation in
    let t_why_gen = Unix.gettimeofday () in
    let why_ast =
      Why_compile.compile_program_ast_from_ir_nodes asts.instrumentation
    in
    let ptree = why_ast.Why_compile.mlw in
    let why_text, why_spans = Why_text_render.emit_program_ast_with_spans why_ast in
    External_timing.record_why_gen ~elapsed_s:(Unix.gettimeofday () -. t_why_gen);
    let t_vc_smt = Unix.gettimeofday () in
    let vc_tasks = Why_task_dump_render.dump_why3_tasks_with_attrs_of_ptree ~ptree in
    let vc_text, vc_spans_ordered =
      if cfg.generate_vc_text then join_blocks_with_spans ~sep:"\n(* ---- goal ---- *)\n" vc_tasks else ("", [])
    in
    let smt_tasks = Why_task_dump_render.dump_smt2_tasks_of_ptree ~ptree in
    let smt_text, smt_spans_ordered =
      if cfg.generate_smt_text then join_blocks_with_spans ~sep:"\n; ---- goal ----\n" smt_tasks else ("", [])
    in
    let _cfg, _main, env, _datadir_opt = Why_task_support.setup_env () in
    let normalized_tasks = Why_task_support.normalize_tasks_of_ptree ~env ~ptree in
    let goal_count = List.length normalized_tasks in
    let vc_ids_ordered = List.init goal_count (fun i -> i + 1) in
    let vc_locs, vc_locs_ordered = ([], []) in
    let program_dot, program_automaton_text = program_automaton_texts asts in
    let guarantee_automaton_text = artifacts.guarantee_automaton_text in
    let assume_automaton_text = artifacts.assume_automaton_text in
    let product_text = artifacts.product_text in
    let canonical_text = artifacts.canonical_text in
    let obligations_map_text_raw = artifacts.obligations_map_text_raw in
    let guarantee_automaton_dot = artifacts.guarantee_automaton_dot in
    let assume_automaton_dot = artifacts.assume_automaton_dot in
    let product_dot = artifacts.product_dot in
    let canonical_dot = artifacts.canonical_dot in
    let dot_text = product_dot in
    let labels_text =
      String.concat "\n\n"
        [ program_automaton_text; guarantee_automaton_text; assume_automaton_text; product_text ]
    in
    let dot_png, dot_png_error =
      if cfg.generate_dot_png && dot_text <> "" then
        Graphviz_render.dot_png_from_text_diagnostic dot_text
      else (None, None)
    in
    let program_png, program_png_error =
      if String.trim program_dot = "" then (None, Some "Program automaton DOT is empty.")
      else Graphviz_render.dot_png_from_text_diagnostic program_dot
    in
    let guarantee_automaton_png, guarantee_automaton_png_error =
      if String.trim guarantee_automaton_dot = "" then
        (None, Some "Guarantee automaton DOT is empty.")
      else Graphviz_render.dot_png_from_text_diagnostic guarantee_automaton_dot
    in
    let assume_automaton_png, assume_automaton_png_error =
      if String.trim assume_automaton_dot = "" then
        (None, Some "Assume automaton DOT is empty.")
      else Graphviz_render.dot_png_from_text_diagnostic assume_automaton_dot
    in
    let product_png, product_png_error =
      if String.trim product_dot = "" then (None, Some "Product automaton DOT is empty.")
      else Graphviz_render.dot_png_from_text_diagnostic product_dot
    in
    let obligations_map_text =
      let taxonomy_text = Obligation_taxonomy.render_summary obligation_summary in
      if String.trim obligations_map_text_raw = "" then
        "-- OBC obligation taxonomy --\n" ^ taxonomy_text
      else obligations_map_text_raw ^ "\n\n-- OBC obligation taxonomy --\n" ^ taxonomy_text
    in
    let goal_results =
      if cfg.prove && not cfg.wp_only then
        let finished = ref [] in
        let _ =
          Why_contract_prove.prove_ptree_with_events ~timeout:cfg.timeout_s
            ptree ~should_cancel:(fun () -> false)
            ~on_goal_start:(fun _ -> ())
            ~on_goal_done:(fun ev ->
              let idx = ev.goal_index in
              let r = ev.result in
              let status = Proof_status_render.of_prover_answer r.prover_result.pr_answer in
              let vcid =
                match List.nth_opt vc_ids_ordered idx with
                | Some id -> Some (string_of_int id)
                | None -> None
              in
              finished := (idx, r.goal_name, status, r.prover_result.pr_time, r.dump_path, vcid) :: !finished)
        in
        List.sort (fun (a, _, _, _, _, _) (b, _, _, _, _, _) -> compare a b) !finished
      else
        List.mapi
          (fun idx _task ->
            let vcid = List.nth vc_ids_ordered idx in
            let stable_id = Printf.sprintf "vc-%03d" (idx + 1) in
            (idx, stable_id, "pending", 0.0, None, Some (string_of_int vcid)))
          normalized_tasks
    in
    External_timing.record_vc_smt ~elapsed_s:(Unix.gettimeofday () -. t_vc_smt);
    let goal_result_tbl = Hashtbl.create (List.length goal_results * 2 + 1) in
    List.iter
      (fun ((idx, _, _, _, _, _) as goal_result) -> Hashtbl.replace goal_result_tbl idx goal_result)
      goal_results;
    let proof_traces =
      List.mapi (fun idx _task -> idx) normalized_tasks
      |> List.filter_map (fun idx ->
             let _goal_idx, goal_name, status, time_s, dump_path, raw_vcid =
               match Hashtbl.find_opt goal_result_tbl idx with
               | Some goal -> goal
               | None ->
                   let fallback_id = Printf.sprintf "vc-%03d" (idx + 1) in
                   ( idx,
                     fallback_id,
                     "pending",
                     0.0,
                     None,
                     Some (string_of_int (List.nth vc_ids_ordered idx)) )
             in
             let stable_id = Printf.sprintf "vc-%03d" (idx + 1) in
             let native_core, native_probe =
               if not cfg.compute_proof_diagnostics then (None, None)
               else
                 match String.lowercase_ascii status with
                 | "valid" | "proved" -> (None, None)
                 | "pending" -> (None, None)
                 | _ ->
                     let native_probe =
                       Why_native_probe.native_solver_probe_for_goal_of_ptree ~timeout:cfg.timeout_s
                         ~ptree ~goal_index:idx ()
                     in
                     (None, native_probe)
             in
             let diagnostic =
               Proof_diagnostics.diagnostic_for_trace ~status ~goal_text:goal_name
                 ~native_core ~native_probe
             in
             Some {
               Pipeline_types.goal_index = idx;
               stable_id;
               goal_name;
               status;
               solver_status = (match native_probe with Some probe -> probe.status | None -> status);
               time_s;
               source = "";
               node = None;
               transition = None;
               obligation_kind = "unknown";
               obligation_family = None;
               obligation_category = None;
               vc_id = raw_vcid;
               source_span = None;
               why_span = None;
               vc_span = List.nth_opt vc_spans_ordered idx;
               smt_span = List.nth_opt smt_spans_ordered idx;
               dump_path;
               diagnostic;
             })
    in
    let goals =
      List.map
        (fun (trace : Pipeline_types.proof_trace) ->
          (trace.goal_name, trace.status, trace.time_s, trace.dump_path, trace.vc_id))
        proof_traces
    in
    Ok {
      Pipeline_types.why_text;
      vc_text;
      smt_text;
      dot_text;
      labels_text;
      program_automaton_text;
      guarantee_automaton_text;
      assume_automaton_text;
      product_text;
      canonical_text;
      obligations_map_text;
      program_dot;
      guarantee_automaton_dot;
      assume_automaton_dot;
      product_dot;
      canonical_dot;
      stage_meta = stage_meta infos @ [ ("obligations_taxonomy", Obligation_taxonomy.to_stage_meta obligation_summary) ];
      goals;
      proof_traces;
      vc_locs;
      vc_locs_ordered;
      vc_spans_ordered =
        List.map
          (fun (span : Pipeline_types.text_span) -> (span.start_offset, span.end_offset))
          vc_spans_ordered;
      why_spans;
      vc_ids_ordered;
      why_time_s = 0.0;
      automata_generation_time_s = 0.0;
      automata_build_time_s = 0.0;
      why3_prep_time_s = 0.0;
      dot_png;
      dot_png_error;
      program_png;
      program_png_error;
      guarantee_automaton_png;
      guarantee_automaton_png_error;
      assume_automaton_png;
      assume_automaton_png_error;
      product_png;
      product_png_error;
      historical_clauses_text = "";
      eliminated_clauses_text = "";
    }
  with exn -> Error (Pipeline_types.Stage_error (Printexc.to_string exn))
