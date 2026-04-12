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

let instrumentation_pass = Instrumentation_artifacts.instrumentation_pass

let why_pass ~input_file =
  match Pipeline_build.build_ast_with_info ~input_file () with
  | Error _ as e -> e
  | Ok (asts, infos) ->
      let why_ast = Why_compile.compile_program_ast_from_ir_nodes asts.instrumentation in
      let why_text = Why_text_render.emit_program_ast why_ast in
      Ok { Pipeline_types.why_text; stage_meta = Pipeline_outputs.stage_meta infos }

let obligations_pass ~input_file =
  match Pipeline_build.build_ast_with_info ~input_file () with
  | Error _ as e -> e
  | Ok (asts, _infos) ->
      Ok (Why_pipeline.obligations_pass asts.instrumentation)

let normalized_program ~input_file =
  match Pipeline_build.build_ast_with_info ~input_file () with
  | Error _ as err -> err
  | Ok (asts, _infos) ->
      Ok
        (Ir_text_program_view_render.render_program
           ~source_program:(Some asts.automata_generation)
           asts.instrumentation)

let ir_pretty_dump ~input_file =
  match Pipeline_build.build_ast_with_info ~input_file () with
  | Error _ as err -> err
  | Ok (asts, infos) ->
      let _ = infos in
      let program : Ir.program_ir = { nodes = asts.instrumentation } in
      Ok
        (Ir_text_proof_view_render.render_pretty_program
           ~source_program:(Some asts.automata_generation)
           program)

let compile_object = Instrumentation_artifacts.compile_object

let run =
  Compile_run.run ~build_ast_with_info:Pipeline_build.build_ast_with_info
    ~build_outputs:Pipeline_outputs.build_outputs

let run_with_callbacks =
  Compile_run.run_with_callbacks ~build_ast_with_info:Pipeline_build.build_ast_with_info
    ~build_outputs:Pipeline_outputs.build_outputs
