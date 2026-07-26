module Contract = Kairos_engine_contract.Contract
module Internal = Pipeline_types

let proof_encoding_to_internal = function
  | Contract.Explicit_product -> Internal.Explicit_product

let proof_optimizations_to_internal
    (options : Contract.proof_optimizations) : Internal.proof_optimizations =
  {
    group_public_non_w_guarantees =
      options.group_public_non_w_guarantees;
    share_why3_facts = options.share_why3_facts;
    simplify_why3_formulas = options.simplify_why3_formulas;
    slice_why3_transition_bodies = options.slice_why3_transition_bodies;
    simplify_why3_runtime_actions = options.simplify_why3_runtime_actions;
    deduplicate_why3_terms = options.deduplicate_why3_terms;
    group_why3_product_steps = options.group_why3_product_steps;
    why3_product_step_group_max_cost =
      options.why3_product_step_group_max_cost;
  }

let config_to_internal (config : Contract.config) : Internal.config =
  {
    input_file = config.input_file;
    wp_only = config.wp_only;
    smoke_tests = config.smoke_tests;
    timeout_s = config.timeout_s;
    compute_proof_diagnostics = config.compute_proof_diagnostics;
    prove = config.prove;
    proof_jobs = config.proof_jobs;
    generate_why_text = config.generate_why_text;
    generate_vc_text = config.generate_vc_text;
    generate_smt_text = config.generate_smt_text;
    generate_dot_png = config.generate_dot_png;
    dump_failed_smt = config.dump_failed_smt;
    collect_ir_metrics = config.collect_ir_metrics;
    proof_progress_path = config.proof_progress_path;
    stop_on_first_nonvalid = config.stop_on_first_nonvalid;
    proof_encoding = proof_encoding_to_internal config.proof_encoding;
    proof_optimizations =
      proof_optimizations_to_internal config.proof_optimizations;
  }

let error_to_contract = function
  | Internal.Parse_error message -> Contract.Parse_error message
  | Internal.Elaboration_error message ->
      Contract.Elaboration_error message
  | Internal.Type_error message -> Contract.Type_error message
  | Internal.Well_formedness_error message ->
      Contract.Well_formedness_error message
  | Internal.Flow_error message -> Contract.Flow_error message
  | Internal.Why3_error message -> Contract.Why3_error message
  | Internal.Prove_error message -> Contract.Prove_error message
  | Internal.Io_error message -> Contract.Io_error message
  | Internal.Internal_error message -> Contract.Internal_error message

let source_location_to_contract (location : Loc.loc) :
    Contract.source_location =
  {
    line = location.line;
    column = location.col;
    end_line = location.line_end;
    end_column = location.col_end;
  }

let text_span_to_contract (span : Internal.text_span) : Contract.text_span =
  {
    start_offset = span.start_offset;
    end_offset = span.end_offset;
  }

let diagnostic_to_contract (diagnostic : Internal.proof_diagnostic) :
    Contract.proof_diagnostic =
  {
    category = diagnostic.category;
    summary = diagnostic.summary;
    detail = diagnostic.detail;
    probable_cause = diagnostic.probable_cause;
    missing_elements = diagnostic.missing_elements;
    goal_symbols = diagnostic.goal_symbols;
    analysis_method = diagnostic.analysis_method;
    solver_detail = diagnostic.solver_detail;
    native_unsat_core_solver = diagnostic.native_unsat_core_solver;
    native_unsat_core_hypothesis_ids =
      diagnostic.native_unsat_core_hypothesis_ids;
    native_counterexample_solver = diagnostic.native_counterexample_solver;
    native_counterexample_model = diagnostic.native_counterexample_model;
    kairos_core_hypotheses = diagnostic.kairos_core_hypotheses;
    why3_noise_hypotheses = diagnostic.why3_noise_hypotheses;
    relevant_hypotheses = diagnostic.relevant_hypotheses;
    context_hypotheses = diagnostic.context_hypotheses;
    unused_hypotheses = diagnostic.unused_hypotheses;
    suggestions = diagnostic.suggestions;
    limitations = diagnostic.limitations;
  }

let proof_trace_to_contract (trace : Internal.proof_trace) :
    Contract.proof_trace =
  {
    goal_index = trace.goal_index;
    stable_id = trace.stable_id;
    goal_name = trace.goal_name;
    status = trace.status;
    solver_status = trace.solver_status;
    time_s = trace.time_s;
    why3_prepare_s = trace.why3_prepare_s;
    why3_print_s = trace.why3_print_s;
    why3_spawn_s = trace.why3_spawn_s;
    why3_wait_s = trace.why3_wait_s;
    why3_solver_s = trace.why3_solver_s;
    source = trace.source;
    node = trace.node;
    transition = trace.transition;
    obligation_kind = trace.obligation_kind;
    obligation_family = trace.obligation_family;
    obligation_category = trace.obligation_category;
    vc_id = trace.vc_id;
    source_span = Option.map source_location_to_contract trace.source_span;
    why_span = Option.map text_span_to_contract trace.why_span;
    vc_span = Option.map text_span_to_contract trace.vc_span;
    smt_span = Option.map text_span_to_contract trace.smt_span;
    dump_path = trace.dump_path;
    diagnostic = diagnostic_to_contract trace.diagnostic;
  }

let automata_outputs_to_contract (outputs : Internal.automata_outputs) :
    Contract.automata_outputs =
  {
    dot_text = outputs.dot_text;
    labels_text = outputs.labels_text;
    program_automaton_text = outputs.program_automaton_text;
    guarantee_automaton_text = outputs.guarantee_automaton_text;
    assume_automaton_text = outputs.assume_automaton_text;
    product_text = outputs.product_text;
    canonical_text = outputs.canonical_text;
    obligations_map_text = outputs.obligations_map_text;
    program_dot = outputs.program_dot;
    guarantee_automaton_dot = outputs.guarantee_automaton_dot;
    assume_automaton_dot = outputs.assume_automaton_dot;
    product_dot = outputs.product_dot;
    canonical_dot = outputs.canonical_dot;
    dot_png = outputs.dot_png;
    dot_png_error = outputs.dot_png_error;
    program_png = outputs.program_png;
    program_png_error = outputs.program_png_error;
    guarantee_automaton_png = outputs.guarantee_automaton_png;
    guarantee_automaton_png_error = outputs.guarantee_automaton_png_error;
    assume_automaton_png = outputs.assume_automaton_png;
    assume_automaton_png_error = outputs.assume_automaton_png_error;
    product_png = outputs.product_png;
    product_png_error = outputs.product_png_error;
    flow_meta = outputs.flow_meta;
    historical_clauses_text = outputs.historical_clauses_text;
    eliminated_clauses_text = outputs.eliminated_clauses_text;
  }

let why_outputs_to_contract (outputs : Internal.why_outputs) :
    Contract.why_outputs =
  { why_text = outputs.why_text; flow_meta = outputs.flow_meta }

let obligations_outputs_to_contract (outputs : Internal.obligations_outputs) :
    Contract.obligations_outputs =
  { vc_text = outputs.vc_text; smt_text = outputs.smt_text }

let cost_report_outputs_to_contract (outputs : Internal.cost_report_outputs) :
    Contract.cost_report_outputs =
  { cost_report_json = outputs.cost_report_json }

let outputs_to_contract (outputs : Internal.outputs) : Contract.outputs =
  {
    why_text = outputs.why_text;
    vc_text = outputs.vc_text;
    smt_text = outputs.smt_text;
    dot_text = outputs.dot_text;
    labels_text = outputs.labels_text;
    program_automaton_text = outputs.program_automaton_text;
    guarantee_automaton_text = outputs.guarantee_automaton_text;
    assume_automaton_text = outputs.assume_automaton_text;
    product_text = outputs.product_text;
    canonical_text = outputs.canonical_text;
    obligations_map_text = outputs.obligations_map_text;
    program_dot = outputs.program_dot;
    guarantee_automaton_dot = outputs.guarantee_automaton_dot;
    assume_automaton_dot = outputs.assume_automaton_dot;
    product_dot = outputs.product_dot;
    canonical_dot = outputs.canonical_dot;
    flow_meta = outputs.flow_meta;
    goals = outputs.goals;
    proof_traces = List.map proof_trace_to_contract outputs.proof_traces;
    vc_locs =
      List.map
        (fun (index, location) ->
          (index, source_location_to_contract location))
        outputs.vc_locs;
    vc_locs_ordered =
      List.map source_location_to_contract outputs.vc_locs_ordered;
    vc_spans_ordered = outputs.vc_spans_ordered;
    why_spans = outputs.why_spans;
    vc_ids_ordered = outputs.vc_ids_ordered;
    why_time_s = outputs.why_time_s;
    automata_generation_time_s = outputs.automata_generation_time_s;
    automata_build_time_s = outputs.automata_build_time_s;
    why3_prep_time_s = outputs.why3_prep_time_s;
    dot_png = outputs.dot_png;
    dot_png_error = outputs.dot_png_error;
    program_png = outputs.program_png;
    program_png_error = outputs.program_png_error;
    guarantee_automaton_png = outputs.guarantee_automaton_png;
    guarantee_automaton_png_error = outputs.guarantee_automaton_png_error;
    assume_automaton_png = outputs.assume_automaton_png;
    assume_automaton_png_error = outputs.assume_automaton_png_error;
    product_png = outputs.product_png;
    product_png_error = outputs.product_png_error;
    historical_clauses_text = outputs.historical_clauses_text;
    eliminated_clauses_text = outputs.eliminated_clauses_text;
  }
