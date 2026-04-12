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
  type snapshot = Pipeline_types.pipeline_snapshot

  let build_snapshot ~input_file = Pipeline_build.build_ast_with_info ~input_file ()
end

module Outputs = struct
  type snapshot = Pipeline_types.pipeline_snapshot

  let build_outputs = Pipeline_outputs.build_outputs
end

module Instrumentation = struct
  let instrumentation_pass = Instrumentation_artifacts.instrumentation_pass
end

module Why_text = struct
  type snapshot = Pipeline_types.pipeline_snapshot

  let why_text ~(snapshot : snapshot) : Pipeline_types.why_outputs =
    let why_ast = Why_compile.compile_program_ast_from_ir_nodes snapshot.asts.instrumentation in
    let why_text = Why_text_render.emit_program_ast why_ast in
    { Pipeline_types.why_text; flow_meta = Pipeline_outputs.flow_meta snapshot.infos }
end

module Obligations = struct
  type snapshot = Pipeline_types.pipeline_snapshot

  let obligations ~(snapshot : snapshot) : Pipeline_types.obligations_outputs =
    let out = Why_pipeline.obligations_pass snapshot.asts.instrumentation in
    { Pipeline_types.vc_text = out.vc_text; smt_text = out.smt_text }
end

module Ir_render = struct
  type snapshot = Pipeline_types.pipeline_snapshot

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
  type snapshot = Pipeline_types.pipeline_snapshot

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

module Ports = struct
  type snapshot = Pipeline_types.pipeline_snapshot

  module Snapshot = Snapshot
  module Outputs = Outputs
  module Instrumentation = Instrumentation
  module Why_text = Why_text
  module Obligations = Obligations
  module Ir_render = Ir_render
  module Timing = Timing
  module Proof_events = Proof_events
end

let compile_object = Instrumentation_artifacts.compile_object
