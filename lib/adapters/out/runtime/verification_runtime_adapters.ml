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

module Snapshot = struct
  type snapshot = Runtime_snapshot.pipeline_snapshot

  let build_snapshot ~frontend = Pipeline_build.build_snapshot_from_frontend ~frontend
end

module Outputs = struct
  type snapshot = Runtime_snapshot.pipeline_snapshot

  let build_outputs = Pipeline_outputs.build_outputs
end

let instrumentation_from_snapshot ~generate_png ~(snapshot : Runtime_snapshot.pipeline_snapshot) =
  match Pipeline_artifact_bundle.build ~asts:snapshot.asts with
  | Error msg -> Error (Pipeline_types.Flow_error msg)
  | Ok artifacts ->
      Ok
        (Output_mapper.map_automata_outputs ~generate_png ~snapshot
           ~artifacts)

module Why_text = struct
  type snapshot = Runtime_snapshot.pipeline_snapshot

  let why_text ~(snapshot : snapshot) : Pipeline_types.why_outputs =
    let why_ast = Why_compile.compile_program_ast_from_ir_nodes snapshot.asts.instrumentation in
    let why_text = Why_text_render.emit_program_ast why_ast in
    { Pipeline_types.why_text; flow_meta = Pipeline_outputs.flow_meta snapshot.infos }
end

module Obligations = struct
  type snapshot = Runtime_snapshot.pipeline_snapshot

  let obligations ~(snapshot : snapshot) : Pipeline_types.obligations_outputs =
    let out = Why_pipeline.obligations_pass snapshot.asts.instrumentation in
    { Pipeline_types.vc_text = out.vc_text; smt_text = out.smt_text }
end

module Ir_render = struct
  type snapshot = Runtime_snapshot.pipeline_snapshot

  let normalized_program ~(snapshot : snapshot) : string =
    Ir_text_program_view_render.render_program ~source_program:(Some snapshot.asts.automata_generation)
      snapshot.asts.instrumentation

  let pretty_program ~(snapshot : snapshot) : string =
    let program : Ir.program_ir = { nodes = snapshot.asts.instrumentation } in
    Ir_text_proof_view_render.render_pretty_program
      ~source_program:(Some snapshot.asts.automata_generation)
      program
end

module Timing = struct
  type snapshot = External_timing.snapshot

  let now_s = Unix.gettimeofday
  let snapshot = External_timing.snapshot

  let diff ~before ~after_ : Application_ports.timing_counters =
    let d = External_timing.diff ~before ~after_ in
    {
      spot_s = d.spot_s;
      spot_calls = d.spot_calls;
      z3_s = d.z3_s;
      z3_calls = d.z3_calls;
      product_s = d.product_s;
      canonical_s = d.canonical_s;
      why_gen_s = d.why_gen_s;
      vc_smt_s = d.vc_smt_s;
    }
end

module Proof_events = struct
  type snapshot = Runtime_snapshot.pipeline_snapshot

  let prove_with_events ~timeout_s ~should_cancel ~(snapshot : snapshot)
      ~(vc_ids_ordered : int list) ~on_goal_done : Application_ports.goal_result list =
    let ptree = (Why_compile.compile_program_ast_from_ir_nodes snapshot.asts.instrumentation).Why_compile.mlw in
    let finished = ref [] in
    let _ =
      Why_contract_prove.prove_ptree_with_events ~timeout:timeout_s ptree ~should_cancel
        ~on_goal_start:(fun _ -> ()) ~on_goal_done:(fun ev ->
          let idx = ev.goal_index in
          let r = ev.result in
          let status = Proof_status_render.of_prover_answer r.prover_result.pr_answer in
          let vcid =
            match List.nth_opt vc_ids_ordered idx with
            | Some id -> Some (string_of_int id)
            | None -> None
          in
          let item = (idx, r.goal_name, status, r.prover_result.pr_time, r.dump_path, vcid) in
          finished := item :: !finished;
          on_goal_done item)
    in
    List.sort (fun (a, _, _, _, _, _) (b, _, _, _, _, _) -> Int.compare a b) !finished
end

let compile_object_from_snapshot ~input_file ~(snapshot : Runtime_snapshot.pipeline_snapshot) :
    (Kairos_object.t, Pipeline_types.error) result =
  match Pipeline_artifact_bundle.build ~asts:snapshot.asts with
  | Error msg -> Error (Pipeline_types.Flow_error msg)
  | Ok artifacts ->
      let parse_info =
        Option.value snapshot.infos.parse ~default:Flow_info.empty_parse_info
      in
      Kairos_object.build ~source_path:input_file
        ~source_hash:parse_info.text_hash
        ~imports:snapshot.asts.imports
        ~program:snapshot.asts.verification_model
        ~runtime_program:snapshot.asts.automata_generation
        ~kernel_ir_nodes:artifacts.kernel_ir_nodes
      |> Result.map_error (fun msg -> Pipeline_types.Flow_error msg)
