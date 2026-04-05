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

(** Why/VC/SMT export passes extracted from the v2 pipeline implementation. *)

let join_blocks ~sep blocks =
  let b = Buffer.create 4096 in
  List.iteri
    (fun i s ->
      if i > 0 then Buffer.add_string b sep;
      Buffer.add_string b s)
    blocks;
  Buffer.contents b

let compile_why_text ~prefix_fields ~disable_why3_optimizations ~(asts : Pipeline_types.ast_stages)
    ~(infos : Pipeline_types.stage_infos) =
  let _ = infos in
  let backend_context = Why_runtime_view.build_backend_phase_context asts.automata_generation in
  let why_ast =
    Emit.compile_program_ast_from_ir_nodes ~prefix_fields ~disable_why3_optimizations
      ~backend_context asts.instrumentation
  in
  Emit.emit_program_ast why_ast

let why_pass ~build_ast_with_info ~stage_meta ~prefix_fields ~disable_why3_optimizations
    ~input_file =
  match build_ast_with_info ~input_file () with
  | Error _ as e -> e
  | Ok (asts, infos) ->
      let why_text = compile_why_text ~prefix_fields ~disable_why3_optimizations ~asts ~infos in
      Ok { Pipeline_types.why_text = why_text; stage_meta = stage_meta infos }

let obligations_pass ~build_ast_with_info ~prefix_fields ~disable_why3_optimizations ~prover
    ~input_file =
  match build_ast_with_info ~input_file () with
  | Error _ as e -> e
  | Ok (asts, infos) ->
      let why_text = compile_why_text ~prefix_fields ~disable_why3_optimizations ~asts ~infos in
      let vc_text =
        join_blocks ~sep:"\n(* ---- goal ---- *)\n"
          (Why_contract_prove.dump_why3_tasks_with_attrs ~text:why_text)
      in
      let smt_text =
        join_blocks ~sep:"\n; ---- goal ----\n"
          (Why_contract_prove.dump_smt2_tasks ~prover ~text:why_text)
      in
      Ok { Pipeline_types.vc_text = vc_text; smt_text }
