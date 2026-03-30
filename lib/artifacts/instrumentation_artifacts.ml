(** Instrumentation/automata artifact pass extracted from the v2 pipeline implementation. *)

let instrumentation_pass ~build_ast_with_info ~stage_meta ~instrumentation_diag_texts
    ~program_automaton_texts ~generate_png ~input_file =
  match build_ast_with_info ~input_file () with
  | Error _ as e -> e
  | Ok ((asts : Pipeline_types.ast_stages), (infos : Pipeline_types.stage_infos)) ->
      let obligation_summary = Obligation_taxonomy.summarize_program asts.contracts in
      let instrumentation_info =
        Option.value infos.instrumentation ~default:Stage_info.empty_instrumentation_info
      in
      let guarantee_automaton_text, assume_automaton_text, product_text, canonical_text,
          obligations_map_text_raw, guarantee_automaton_tex, assume_automaton_tex, product_tex,
          product_tex_explicit, canonical_tex, guarantee_automaton_dot, assume_automaton_dot,
          product_dot, product_dot_explicit, canonical_dot =
        instrumentation_diag_texts infos
      in
      let obligations_map_text =
        let taxonomy_text = Obligation_taxonomy.render_summary obligation_summary in
        if String.trim obligations_map_text_raw = "" then
          "-- OBC obligation taxonomy --\n" ^ taxonomy_text
        else
          obligations_map_text_raw ^ "\n\n-- OBC obligation taxonomy --\n" ^ taxonomy_text
      in
      let dot_text, labels_text =
        Artifact_render_monitor.dot_monitor_program ~show_labels:false asts.automata_generation
      in
      let program_dot, program_automaton_text = program_automaton_texts asts in
      let dot_png, dot_png_error =
        if generate_png then Graphviz_render.dot_png_from_text_diagnostic dot_text else (None, None)
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
      Ok
        {
          Pipeline_types.dot_text = dot_text;
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
            stage_meta infos
            @ [ ("obligations_taxonomy", Obligation_taxonomy.to_stage_meta obligation_summary) ];
          historical_clauses_text =
            instrumentation_info.kernel_ir_nodes
            |> List.concat_map Ir_render_kernel.render_historical_clauses
            |> String.concat "\n";
          eliminated_clauses_text =
            instrumentation_info.kernel_ir_nodes
            |> List.concat_map Ir_render_kernel.render_eliminated_clauses
            |> String.concat "\n";
        }
