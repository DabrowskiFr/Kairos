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

let join_blocks_with_spans ~sep blocks =
  let b = Buffer.create 4096 in
  let spans = ref [] in
  let offset = ref 0 in
  List.iteri
    (fun i s ->
      if i > 0 then (
        Buffer.add_string b sep;
        offset := !offset + String.length sep);
      let start_offset = !offset in
      Buffer.add_string b s;
      offset := !offset + String.length s;
      spans :=
        { Pipeline_types.start_offset = start_offset; end_offset = !offset } :: !spans)
    blocks;
  (Buffer.contents b, List.rev !spans)

let stage_meta (infos : Pipeline_types.stage_infos) : (string * (string * string) list) list =
  let p = Option.value ~default:Stage_info.empty_parse_info infos.parse in
  let a = Option.value ~default:Stage_info.empty_automata_info infos.automata_generation in
  let c = Option.value ~default:Stage_info.empty_contracts_info infos.contracts in
  let i = Option.value ~default:Stage_info.empty_instrumentation_info infos.instrumentation in
  [
    ("user", [ ("source_path", Option.value ~default:"" p.source_path); ("warnings", string_of_int (List.length p.warnings)) ]);
    ("automata", [ ("states", string_of_int a.residual_state_count); ("edges", string_of_int a.residual_edge_count) ]);
    ("contracts", [ ("origins", string_of_int (List.length c.contract_origin_map)); ("warnings", string_of_int (List.length c.warnings)) ]);
    ("instrumentation", [ ("obligations_lines", string_of_int (List.length i.obligations_lines)) ]);
    ( "graph_metrics",
      [
        ("require_automata_states", string_of_int i.require_automata_state_count);
        ("require_automata_edges", string_of_int i.require_automata_edge_count);
        ("ensures_automata_states", string_of_int i.ensures_automata_state_count);
        ("ensures_automata_edges", string_of_int i.ensures_automata_edge_count);
        ("product_edges_full", string_of_int i.product_edge_count_full);
        ("product_edges_live", string_of_int i.product_edge_count_live);
        ("product_states_full", string_of_int i.product_state_count_full);
        ("product_states_live", string_of_int i.product_state_count_live);
      ] );
    ( "canonical_metrics",
      [
        ("canonical_contracts", string_of_int i.canonical_contract_count);
        ("canonical_cases_safe", string_of_int i.canonical_case_safe_count);
        ( "canonical_cases_bad_assumption",
          string_of_int i.canonical_case_bad_assumption_count );
        ( "canonical_cases_bad_guarantee",
          string_of_int i.canonical_case_bad_guarantee_count );
      ] );
  ]

let instrumentation_diag_texts (infos : Pipeline_types.stage_infos) :
    string
    * string
    * string
    * string
    * string
    * string
    * string
    * string
    * string
    * string
    * string
    * string
    * string
    * string
    * string =
  let i = Option.value ~default:Stage_info.empty_instrumentation_info infos.instrumentation in
  let obligations_text =
    let base = String.concat "\n" i.obligations_lines in
    let kernel = String.concat "\n" i.kernel_pipeline_lines in
    match (String.trim base, String.trim kernel) with
    | "", "" -> ""
    | _, "" -> base
    | "", _ -> kernel
    | _ -> base ^ "\n\n" ^ kernel
  in
  ( String.concat "\n" i.guarantee_automaton_lines,
    String.concat "\n" i.assume_automaton_lines,
    String.concat "\n" i.product_lines,
    String.concat "\n" i.canonical_lines,
    obligations_text,
    i.guarantee_automaton_tex,
    i.assume_automaton_tex,
    i.product_tex,
    i.product_tex_explicit,
    i.canonical_tex,
    i.guarantee_automaton_dot,
    i.assume_automaton_dot,
    i.product_dot,
    i.product_dot_explicit,
    i.canonical_dot )

let program_automaton_texts (asts : Pipeline_types.ast_stages) : string * string =
  match asts.automata_generation with
  | [] -> ("", "")
  | node :: _ ->
      Ir_render_product.render_program_automaton ~node_name:node.semantics.sem_nname
        ~node:(From_ast.of_ast_node node)

let unique_preserve_order xs =
  let seen = Hashtbl.create 16 in
  List.filter
    (fun x ->
      if x = "" || Hashtbl.mem seen x then false
      else (
        Hashtbl.replace seen x ();
        true))
    xs

let option_join = function Some x -> x | None -> None

let matches_selected_goal ~(cfg : Pipeline_types.config) idx =
  match cfg.selected_goal_index with None -> true | Some selected -> idx = selected

let build_outputs ~(cfg : Pipeline_types.config) ~(asts : Pipeline_types.ast_stages)
    ~(infos : Pipeline_types.stage_infos) :
    (Pipeline_types.outputs, Pipeline_types.error) result =
  try
    let obligation_summary = Obligation_taxonomy.summarize_program asts.contracts in
    let instrumentation_info =
      Option.value infos.instrumentation ~default:Stage_info.empty_instrumentation_info
    in
    let t_why_gen = Unix.gettimeofday () in
    let why_ast =
      Emit.compile_program_ast_from_ir_nodes ~prefix_fields:cfg.prefix_fields
        ~disable_why3_optimizations:cfg.disable_why3_optimizations
        asts.instrumentation
    in
    let why_text, why_spans = Emit.emit_program_ast_with_spans why_ast in
    External_timing.record_why_gen ~elapsed_s:(Unix.gettimeofday () -. t_why_gen);
    let why_span_tbl = Hashtbl.create (List.length why_spans * 2 + 1) in
    List.iter
      (fun (wid, (start_offset, end_offset)) ->
        Hashtbl.replace why_span_tbl wid
          { Pipeline_types.start_offset = start_offset; end_offset })
      why_spans;
    let t_vc_smt = Unix.gettimeofday () in
    let vc_tasks = Why_contract_prove.dump_why3_tasks_with_attrs ~text:why_text in
    let vc_text, vc_spans_ordered =
      if cfg.generate_vc_text then join_blocks_with_spans ~sep:"\n(* ---- goal ---- *)\n" vc_tasks else ("", [])
    in
    let smt_tasks = Why_contract_prove.dump_smt2_tasks ~prover:cfg.prover ~text:why_text in
    let smt_text, smt_spans_ordered =
      if cfg.generate_smt_text then join_blocks_with_spans ~sep:"\n; ---- goal ----\n" smt_tasks else ("", [])
    in
    let task_sequents = Why_contract_prove.task_sequents ~text:why_text in
    let task_structured_sequents = Why_contract_prove.task_structured_sequents ~text:why_text in
    let task_goal_wids = Why_contract_prove.task_goal_wids ~text:why_text in
    let task_state_pairs = Why_contract_prove.task_state_pairs ~text:why_text in
    let vc_ids_ordered = Proof_diagnostics.vc_ids_of_task_goal_ids task_goal_wids in
    let vc_locs, vc_locs_ordered = ([], []) in
    let vc_loc_tbl = Hashtbl.create (List.length vc_locs * 2 + 1) in
    List.iter (fun (id, loc) -> Hashtbl.replace vc_loc_tbl id loc) vc_locs;
    let formula_records = Proof_diagnostics.build_formula_records asts.contracts in
    let formula_record_tbl = Proof_diagnostics.formula_record_table formula_records in
    let vc_sources =
      List.mapi
        (fun idx why_ids ->
          let vcid = List.nth vc_ids_ordered idx in
          let record =
            Proof_diagnostics.resolve_formula_record ~records:formula_record_tbl ~why_ids
          in
          let source =
            Proof_diagnostics.source_from_record_or_state ~record
              ~state_pair:(List.nth_opt task_state_pairs idx |> option_join)
              ~obc_program:(List.map Ir.to_ast_node asts.contracts)
          in
          (vcid, source))
        task_goal_wids
      |> List.filter (fun (vcid, _source) ->
             match cfg.selected_goal_index with
             | None -> true
             | Some selected -> List.nth_opt vc_ids_ordered selected = Some vcid)
    in
    let dot_text, labels_text =
      Artifact_render_monitor.dot_monitor_program ~show_labels:false asts.automata_generation
    in
    let dot_png, dot_png_error =
      if cfg.generate_dot_png && dot_text <> "" then Graphviz_render.dot_png_from_text_diagnostic dot_text
      else (None, None)
    in
    let program_dot, program_automaton_text = program_automaton_texts asts in
    let guarantee_automaton_text, assume_automaton_text, product_text, canonical_text,
        obligations_map_text_raw, guarantee_automaton_tex, assume_automaton_tex, product_tex,
        product_tex_explicit, canonical_tex, guarantee_automaton_dot, assume_automaton_dot,
        product_dot, product_dot_explicit, canonical_dot =
      instrumentation_diag_texts infos
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
        let _summary, _ =
          Why_contract_prove.prove_text_detailed_with_callbacks ~timeout:cfg.timeout_s ~prover:cfg.prover
            ?prover_cmd:cfg.prover_cmd ?selected_goal_index:cfg.selected_goal_index ~text:why_text
            ~vc_ids_ordered:(Some vc_ids_ordered) ~should_cancel:(fun () -> false)
            ~on_goal_start:(fun _ _ -> ())
            ~on_goal_done:(fun idx goal status time_s dump_path source vcid ->
              finished := (idx, goal, status, time_s, dump_path, source, vcid) :: !finished)
            ()
        in
        List.sort (fun (a, _, _, _, _, _, _) (b, _, _, _, _, _, _) -> compare a b) !finished
      else
        List.mapi
          (fun idx why_ids ->
            let vcid = List.nth vc_ids_ordered idx in
            let stable_id = Proof_diagnostics.stable_goal_id idx why_ids in
            (idx, stable_id, "pending", 0.0, None, "", Some (string_of_int vcid)))
          task_goal_wids
        |> List.filter (fun (idx, _, _, _, _, _, _) -> matches_selected_goal ~cfg idx)
    in
    External_timing.record_vc_smt ~elapsed_s:(Unix.gettimeofday () -. t_vc_smt);
    let goal_result_tbl = Hashtbl.create (List.length goal_results * 2 + 1) in
    List.iter
      (fun ((idx, _, _, _, _, _, _) as goal_result) -> Hashtbl.replace goal_result_tbl idx goal_result)
      goal_results;
    let proof_traces =
      List.mapi (fun idx why_ids -> (idx, why_ids)) task_goal_wids
      |> List.filter_map (fun (idx, why_ids) ->
             if not (matches_selected_goal ~cfg idx) then None
             else
               let origin_ids = Proof_diagnostics.collect_origin_ids why_ids in
               let record =
                 Proof_diagnostics.resolve_formula_record ~records:formula_record_tbl ~why_ids
               in
               let source =
                 Proof_diagnostics.source_from_record_or_state ~record
                   ~state_pair:(List.nth_opt task_state_pairs idx |> option_join)
                   ~obc_program:(List.map Ir.to_ast_node asts.contracts)
               in
               let _goal_idx, goal_name, status, time_s, dump_path, _raw_source, raw_vcid =
                 match Hashtbl.find_opt goal_result_tbl idx with
                 | Some goal -> goal
                 | None ->
                     let fallback_id = Proof_diagnostics.stable_goal_id idx why_ids in
                     (idx, fallback_id, "pending", 0.0, None, source, Some (string_of_int (List.nth vc_ids_ordered idx)))
               in
               let stable_id = Proof_diagnostics.stable_goal_id idx why_ids in
               let native_core, native_probe, failing_core =
                 if not cfg.compute_proof_diagnostics then (None, None, None)
                 else
                   match String.lowercase_ascii status with
                   | "valid" | "proved" ->
                       if cfg.selected_goal_index = Some idx then
                         ( Why_contract_prove.native_unsat_core_for_goal ~timeout:cfg.timeout_s ~prover:cfg.prover
                             ~text:why_text ~goal_index:idx (),
                           None,
                           None )
                       else (None, None, None)
                   | "pending" -> (None, None, None)
                   | _ ->
                       let native_probe =
                         Why_contract_prove.native_solver_probe_for_goal ~timeout:cfg.timeout_s ~prover:cfg.prover
                           ~text:why_text ~goal_index:idx ()
                       in
                       let failing_core =
                         match native_probe with
                         | Some { model_text = Some _; _ } -> None
                         | _ ->
                             Why_contract_prove.minimize_failing_hypotheses ~timeout:1 ?prover_cmd:cfg.prover_cmd
                               ~prover:cfg.prover ~text:why_text ~goal_index:idx ()
                       in
                       (None, native_probe, failing_core)
               in
               let diagnostic =
                 Proof_diagnostics.diagnostic_for_trace ~status ~record ~goal_text:goal_name
                   ~structured_sequent:(List.nth_opt task_structured_sequents idx)
                   ~failing_core ~native_core ~native_probe
               in
               let source_span =
                 match List.find_map (fun id -> Hashtbl.find_opt vc_loc_tbl id) origin_ids with
                 | Some _ as loc -> loc
                 | None -> Option.bind record (fun r -> r.loc)
               in
               Some {
                 Pipeline_types.goal_index = idx;
                 stable_id;
                 goal_name;
                 status;
                 solver_status = (match native_probe with Some probe -> probe.status | None -> status);
                 time_s;
                 source;
                 node = Option.bind record (fun r -> r.node);
                 transition = Option.bind record (fun r -> r.transition);
                 obligation_kind = (match record with Some r -> r.obligation_kind | None -> "unknown");
                 obligation_family = Option.bind record (fun r -> r.obligation_family);
                 obligation_category = Option.bind record (fun r -> r.obligation_category);
                 origin_ids;
                 vc_id = raw_vcid;
                 source_span;
                 why_span = List.find_map (fun id -> Proof_diagnostics.lookup_span why_span_tbl id) origin_ids;
                 vc_span = List.nth_opt vc_spans_ordered idx;
                 smt_span = List.nth_opt smt_spans_ordered idx;
                 dump_path;
                 diagnostic;
               })
    in
    let goals =
      List.map
        (fun (trace : Pipeline_types.proof_trace) ->
          (trace.goal_name, trace.status, trace.time_s, trace.dump_path, trace.source, trace.vc_id))
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
      guarantee_automaton_tex;
      assume_automaton_tex;
      product_tex;
      product_tex_explicit;
      canonical_tex;
      product_text;
      canonical_text;
      obligations_map_text;
      program_dot;
      guarantee_automaton_dot;
      assume_automaton_dot;
      product_dot;
      product_dot_explicit;
      canonical_dot;
      stage_meta = stage_meta infos @ [ ("obligations_taxonomy", Obligation_taxonomy.to_stage_meta obligation_summary) ];
      goals;
      proof_traces;
      vc_sources;
      task_sequents;
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
      historical_clauses_text =
        instrumentation_info.kernel_ir_nodes
        |> List.concat_map Ir_render_kernel.render_historical_clauses
        |> String.concat "\n";
      eliminated_clauses_text =
        instrumentation_info.kernel_ir_nodes
        |> List.concat_map Ir_render_kernel.render_eliminated_clauses
        |> String.concat "\n";
    }
  with exn -> Error (Pipeline_types.Stage_error (Printexc.to_string exn))
