open Ast

let join_blocks ~sep blocks =
  let b = Buffer.create 4096 in
  List.iteri
    (fun i s ->
      if i > 0 then Buffer.add_string b sep;
      Buffer.add_string b s)
    blocks;
  Buffer.contents b

let with_smoke_tests (p : Ast.program) : Ast.program =
  let has_false_ensure (t : Ast.transition) =
    List.exists (fun (f : Ast.fo_o) -> f.value = Ast.FFalse) t.ensures
  in
  let add_transition_smoke (t : Ast.transition) : Ast.transition =
    if has_false_ensure t then t
    else { t with ensures = t.ensures @ [ Ast_provenance.with_origin Ast.Internal Ast.FFalse ] }
  in
  List.map (fun (n : Ast.node) -> { n with trans = List.map add_transition_smoke n.trans }) p

let stage_meta (infos : Pipeline.stage_infos) : (string * (string * string) list) list =
  let p = Option.value ~default:Stage_info.empty_parse_info infos.parse in
  let a = Option.value ~default:Stage_info.empty_automata_info infos.automata_generation in
  let c = Option.value ~default:Stage_info.empty_contracts_info infos.contracts in
  let i = Option.value ~default:Stage_info.empty_instrumentation_info infos.instrumentation in
  let o = Option.value ~default:Stage_info.empty_obc_info infos.obc in
  [
    ("user", [ ("source_path", Option.value ~default:"" p.source_path); ("warnings", string_of_int (List.length p.warnings)) ]);
    ("automata", [ ("states", string_of_int a.residual_state_count); ("edges", string_of_int a.residual_edge_count) ]);
    ("contracts", [ ("origins", string_of_int (List.length c.contract_origin_map)); ("warnings", string_of_int (List.length c.warnings)) ]);
    ("instrumentation", [ ("atoms", string_of_int i.atom_count); ("obligations_lines", string_of_int (List.length i.obligations_lines)) ]);
    ("obc", [ ("ghost_locals", string_of_int (List.length o.ghost_locals_added)); ("warnings", string_of_int (List.length o.warnings)) ]);
  ]

let build_ast_with_info ~input_file () :
    (Pipeline.ast_stages * Pipeline.stage_infos, Pipeline.error) result =
  Provenance.reset ();
  try
    let p_parsed, parse_info = Parse_file.parse_file_with_info input_file in
    let p_automaton, automata, automata_info =
      Middle_end.stage_automata_generation_with_info p_parsed
    in
    let p_monitor, automata, instrumentation_info =
      Middle_end.stage_instrumentation_with_info (p_automaton, automata)
    in
    let p_contracts, _automata, contracts_info =
      Middle_end.stage_contracts_with_info (p_monitor, automata)
    in
    let p_obc, obc_info = Obc_stage.run_with_info p_contracts in
    let p_obc_abstract = List.map Abstract_model.of_ast_node p_obc in
    let p_obc_clean =
      List.map
        (fun (n : Ast.node) ->
          {
            n with
            trans = List.map (fun (t : Ast.transition) -> { t with requires = []; ensures = [] }) n.trans;
            attrs = { n.attrs with coherency_goals = [] };
          })
        p_obc
    in
    let asts : Pipeline.ast_stages =
      {
        parsed = p_parsed;
        automata_generation = p_automaton;
        automata;
        contracts = p_contracts;
        instrumentation = p_monitor;
        obc = p_obc_clean;
        obc_abstract = p_obc_abstract;
      }
    in
    let infos : Pipeline.stage_infos =
      {
        parse = Some parse_info;
        automata_generation = Some automata_info;
        contracts = Some contracts_info;
        instrumentation = Some instrumentation_info;
        obc = Some obc_info;
      }
    in
    Ok (asts, infos)
  with exn -> Error (Pipeline.Stage_error (Printexc.to_string exn))

let instrumentation_diag_texts (infos : Pipeline.stage_infos) :
    string * string * string * string * string * string * string * string =
  let i = Option.value ~default:Stage_info.empty_instrumentation_info infos.instrumentation in
  ( String.concat "\n" i.guarantee_automaton_lines,
    String.concat "\n" i.assume_automaton_lines,
    String.concat "\n" i.product_lines,
    String.concat "\n" i.obligations_lines,
    String.concat "\n" i.prune_lines,
    i.guarantee_automaton_dot,
    i.assume_automaton_dot,
    i.product_dot )

let program_automaton_texts (asts : Pipeline.ast_stages) : string * string =
  match asts.automata_generation with
  | [] -> ("", "")
  | node :: _ ->
      Product_debug.render_program_automaton ~node_name:node.nname ~node:(Abstract_model.of_ast_node node)

let build_outputs ~(cfg : Pipeline.config) ~(asts : Pipeline.ast_stages) ~(infos : Pipeline.stage_infos) :
    (Pipeline.outputs, Pipeline.error) result =
  try
    let p_obc_backend =
      let p = List.map Abstract_model.to_ast_node asts.obc_abstract in
      if cfg.smoke_tests then with_smoke_tests p else p
    in
    let obligation_summary = Obligation_taxonomy.summarize_program p_obc_backend in
    let obc_text = List.map Abstract_model.of_ast_node p_obc_backend |> Abstract_model.render_program in
    let why_text = Io.emit_why ~prefix_fields:cfg.prefix_fields ~output_file:None p_obc_backend in
    let vc_tasks = if cfg.generate_vc_text then Why_prove.dump_why3_tasks_with_attrs ~text:why_text else [] in
    let smt_tasks = if cfg.generate_smt_text then Why_prove.dump_smt2_tasks ~prover:cfg.prover ~text:why_text else [] in
    let vc_text = if cfg.generate_vc_text then join_blocks ~sep:"\n(* ---- goal ---- *)\n" vc_tasks else "" in
    let smt_text = if cfg.generate_smt_text then join_blocks ~sep:"\n; ---- goal ----\n" smt_tasks else "" in
    let dot_text, labels_text =
      if cfg.generate_monitor_text then Dot_emit.dot_monitor_program ~show_labels:false asts.automata_generation
      else ("", "")
    in
    let dot_png = if cfg.generate_dot_png && dot_text <> "" then Pipeline.dot_png_from_text dot_text else None in
    let program_dot, program_automaton_text = program_automaton_texts asts in
    let guarantee_automaton_text, assume_automaton_text, product_text, obligations_map_text_raw,
        prune_reasons_text, guarantee_automaton_dot, assume_automaton_dot, product_dot =
      instrumentation_diag_texts infos
    in
    let obligations_map_text =
      let taxonomy_text = Obligation_taxonomy.render_summary obligation_summary in
      if String.trim obligations_map_text_raw = "" then
        "-- OBC obligation taxonomy --\n" ^ taxonomy_text
      else
        obligations_map_text_raw ^ "\n\n-- OBC obligation taxonomy --\n" ^ taxonomy_text
    in
    let goals =
      if cfg.prove && not cfg.wp_only then
        let _summary, goals =
          Why_prove.prove_text_detailed ~timeout:cfg.timeout_s ~prover:cfg.prover ?prover_cmd:cfg.prover_cmd
            ~text:why_text ()
        in
        goals
      else []
    in
    Ok
      {
        Pipeline.obc_text = obc_text;
        why_text;
        vc_text;
        smt_text;
        dot_text;
        labels_text;
        program_automaton_text;
        guarantee_automaton_text;
        assume_automaton_text;
        product_text;
        obligations_map_text;
        prune_reasons_text;
        program_dot;
        guarantee_automaton_dot;
        assume_automaton_dot;
        product_dot;
        stage_meta =
          stage_meta infos
          @ [ ("obligations_taxonomy", Obligation_taxonomy.to_stage_meta obligation_summary) ];
        goals;
        obcplus_sequents = [];
        vc_sources = [];
        task_sequents = [];
        vc_locs = [];
        obcplus_spans = [];
        vc_locs_ordered = [];
        obcplus_spans_ordered = [];
        vc_spans_ordered = [];
        why_spans = [];
        vc_ids_ordered = [];
        obcplus_time_s = 0.0;
        why_time_s = 0.0;
        automata_generation_time_s = 0.0;
        automata_build_time_s = 0.0;
        why3_prep_time_s = 0.0;
        dot_png;
      }
  with exn -> Error (Pipeline.Stage_error (Printexc.to_string exn))

let instrumentation_pass ~generate_png ~input_file =
  match build_ast_with_info ~input_file () with
  | Error _ as e -> e
  | Ok (asts, infos) ->
      let p_obc_backend = List.map Abstract_model.to_ast_node asts.obc_abstract in
      let obligation_summary = Obligation_taxonomy.summarize_program p_obc_backend in
      let guarantee_automaton_text, assume_automaton_text, product_text, obligations_map_text_raw,
          prune_reasons_text, guarantee_automaton_dot, assume_automaton_dot, product_dot =
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
        Dot_emit.dot_monitor_program ~show_labels:false asts.automata_generation
      in
      let program_dot, program_automaton_text = program_automaton_texts asts in
      let dot_png = if generate_png then Pipeline.dot_png_from_text dot_text else None in
      Ok
        {
          Pipeline.dot_text = dot_text;
          labels_text;
          program_automaton_text;
          guarantee_automaton_text;
          assume_automaton_text;
          product_text;
          obligations_map_text;
          prune_reasons_text;
          program_dot;
          guarantee_automaton_dot;
          assume_automaton_dot;
          product_dot;
          dot_png;
          stage_meta =
            stage_meta infos
            @ [ ("obligations_taxonomy", Obligation_taxonomy.to_stage_meta obligation_summary) ];
        }

let obc_pass ~input_file =
  match build_ast_with_info ~input_file () with
  | Error _ as e -> e
  | Ok (asts, infos) ->
      let p_obc = List.map Abstract_model.to_ast_node asts.obc_abstract in
      let obc_text = List.map Abstract_model.of_ast_node p_obc |> Abstract_model.render_program in
      Ok { Pipeline.obc_text = obc_text; stage_meta = stage_meta infos }

let why_pass ~prefix_fields ~input_file =
  match build_ast_with_info ~input_file () with
  | Error _ as e -> e
  | Ok (asts, infos) ->
      let p_obc = List.map Abstract_model.to_ast_node asts.obc_abstract in
      let why_text = Io.emit_why ~prefix_fields ~output_file:None p_obc in
      Ok { Pipeline.why_text = why_text; stage_meta = stage_meta infos }

let obligations_pass ~prefix_fields ~prover ~input_file =
  match build_ast_with_info ~input_file () with
  | Error _ as e -> e
  | Ok (asts, _infos) ->
      let p_obc = List.map Abstract_model.to_ast_node asts.obc_abstract in
      let why_text = Io.emit_why ~prefix_fields ~output_file:None p_obc in
      let vc_text = join_blocks ~sep:"\n(* ---- goal ---- *)\n" (Why_prove.dump_why3_tasks_with_attrs ~text:why_text) in
      let smt_text = join_blocks ~sep:"\n; ---- goal ----\n" (Why_prove.dump_smt2_tasks ~prover ~text:why_text) in
      Ok { Pipeline.vc_text = vc_text; smt_text }

let eval_pass ~input_file ~trace_text ~with_state ~with_locals =
  Pipeline.eval_pass ~input_file ~trace_text ~with_state ~with_locals

let run (cfg : Pipeline.config) =
  match build_ast_with_info ~input_file:cfg.input_file () with
  | Error _ as e -> e
  | Ok (asts, infos) -> build_outputs ~cfg ~asts ~infos

let run_with_callbacks ~should_cancel (cfg : Pipeline.config) ~on_outputs_ready ~on_goals_ready
    ~on_goal_done =
  match run cfg with
  | Error _ as e -> e
  | Ok out ->
      on_outputs_ready { out with goals = [] };
      let goal_names = List.map (fun (g, _, _, _, _, _) -> g) out.goals in
      let vc_ids = List.init (List.length out.goals) (fun i -> i + 1) in
      on_goals_ready (goal_names, vc_ids);
      List.iteri
        (fun i (goal, status, time_s, dump_path, source, vcid) ->
          on_goal_done i goal status time_s dump_path source vcid)
        out.goals;
      if should_cancel () then Error (Pipeline.Stage_error "Request cancelled") else Ok out
