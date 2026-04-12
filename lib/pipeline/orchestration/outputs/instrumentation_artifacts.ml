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

(** Instrumentation/automata artifact pass extracted from the v2 pipeline implementation. *)

let instrumentation_pass ~generate_png ~input_file =
  match Pipeline_build.build_ast_with_info ~input_file () with
  | Error _ as e -> e
  | Ok ((asts : Pipeline_types.ast_stages), (infos : Pipeline_types.stage_infos)) ->
      begin
        match Pipeline_artifact_bundle.build ~asts with
        | Error msg -> Error (Pipeline_types.Stage_error msg)
        | Ok artifacts ->
            let obligation_summary =
              Obligation_taxonomy.summarize_program asts.instrumentation
            in
            let obligations_map_text =
              let taxonomy_text = Obligation_taxonomy.render_summary obligation_summary in
              if String.trim artifacts.obligations_map_text_raw = "" then
                "-- OBC obligation taxonomy --\n" ^ taxonomy_text
              else
                artifacts.obligations_map_text_raw
                ^ "\n\n-- OBC obligation taxonomy --\n"
                ^ taxonomy_text
            in
            let program_dot, program_automaton_text =
              Pipeline_outputs.program_automaton_texts asts
            in
            let dot_text = artifacts.product_dot in
            let labels_text =
              String.concat "\n\n"
                [
                  program_automaton_text;
                  artifacts.guarantee_automaton_text;
                  artifacts.assume_automaton_text;
                  artifacts.product_text;
                ]
            in
            let dot_png, dot_png_error =
              if generate_png then
                Graphviz_render.dot_png_from_text_diagnostic dot_text
              else (None, None)
            in
            let program_png, program_png_error =
              if String.trim program_dot = "" then
                (None, Some "Program automaton DOT is empty.")
              else Graphviz_render.dot_png_from_text_diagnostic program_dot
            in
            let guarantee_automaton_png, guarantee_automaton_png_error =
              if String.trim artifacts.guarantee_automaton_dot = "" then
                (None, Some "Guarantee automaton DOT is empty.")
              else
                Graphviz_render.dot_png_from_text_diagnostic
                  artifacts.guarantee_automaton_dot
            in
            let assume_automaton_png, assume_automaton_png_error =
              if String.trim artifacts.assume_automaton_dot = "" then
                (None, Some "Assume automaton DOT is empty.")
              else
                Graphviz_render.dot_png_from_text_diagnostic
                  artifacts.assume_automaton_dot
            in
            let product_png, product_png_error =
              if String.trim artifacts.product_dot = "" then
                (None, Some "Product automaton DOT is empty.")
              else Graphviz_render.dot_png_from_text_diagnostic artifacts.product_dot
            in
            Ok
              {
                Pipeline_types.dot_text;
                labels_text;
                program_automaton_text;
                guarantee_automaton_text = artifacts.guarantee_automaton_text;
                assume_automaton_text = artifacts.assume_automaton_text;
                product_text = artifacts.product_text;
                canonical_text = artifacts.canonical_text;
                obligations_map_text;
                program_dot;
                guarantee_automaton_dot = artifacts.guarantee_automaton_dot;
                assume_automaton_dot = artifacts.assume_automaton_dot;
                product_dot = artifacts.product_dot;
                canonical_dot = artifacts.canonical_dot;
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
                stage_meta =
                  Pipeline_outputs.stage_meta infos
                  @ [
                      ( "obligations_taxonomy",
                        Obligation_taxonomy.to_stage_meta obligation_summary );
                    ];
                historical_clauses_text = "";
                eliminated_clauses_text = "";
              }
      end

let compile_object ~input_file : (Kairos_object.t, Pipeline_types.error) result =
  match Pipeline_build.build_ast_with_info ~input_file () with
  | Error _ as err -> err
  | Ok (asts, infos) ->
      begin
        match Pipeline_artifact_bundle.build ~asts with
        | Error msg -> Error (Pipeline_types.Stage_error msg)
        | Ok artifacts ->
            let parse_info =
              Option.value infos.parse ~default:Stage_info.empty_parse_info
            in
            Kairos_object.build ~source_path:input_file
              ~source_hash:parse_info.text_hash
              ~imports:(Source_file.imported_paths asts.source)
              ~program:asts.parsed ~runtime_program:asts.automata_generation
              ~kernel_ir_nodes:artifacts.kernel_ir_nodes
            |> Result.map_error (fun msg -> Pipeline_types.Stage_error msg)
      end
