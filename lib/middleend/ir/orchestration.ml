open Ast

let ( let* ) = Result.bind

let build_node_analysis ~(automata : Automata_generation.node_builds) (node : Ir.node) :
    (Product_build.analysis, string) result =
  let* build =
    Result_utils.find_assoc
      ~missing:(fun node_name -> Printf.sprintf "Missing automata build for IR node %s" node_name)
      node.semantics.sem_nname automata
  in
  Ok (Product_build.analyze_node ~build ~node)

let build_analyses ~(automata : Automata_generation.node_builds) (nodes : Ir.node list) :
    ((Ast.ident * Product_build.analysis) list, string) result =
  nodes
  |> List.map (fun (node : Ir.node) ->
         Result.map
           (fun analysis -> (node.semantics.sem_nname, analysis))
           (build_node_analysis ~automata node))
  |> Result_utils.all

let analysis_of_node ~(analyses : (Ast.ident * Product_build.analysis) list) (node : Ir.node) :
    (Product_build.analysis, string) result =
  Result_utils.find_assoc
    ~missing:(fun node_name -> Printf.sprintf "Missing product analysis for IR node %s" node_name)
    node.semantics.sem_nname analyses

let collect_contract_origins (nodes : Ir.node list) : (int * Formula_origin.t option) list =
  let collect_formula acc (formula : Ir.contract_formula) =
    (formula.meta.oid, formula.meta.origin) :: acc
  in
  let collect_product_transition acc (transition : Ir.product_contract) =
    transition.common.requires |> List.fold_left collect_formula acc |> fun acc ->
    transition.common.ensures |> List.fold_left collect_formula acc |> fun acc ->
    transition.cases
    |> List.fold_left
         (fun acc (case : Ir.product_case) ->
           case.propagates |> List.fold_left collect_formula acc |> fun acc ->
           case.ensures |> List.fold_left collect_formula acc |> fun acc ->
           List.fold_left collect_formula acc case.forbidden)
         acc
  in
  nodes
  |> List.fold_left
       (fun acc (node : Ir.node) ->
         List.fold_left collect_product_transition acc node.product_transitions)
       []
  |> List.rev

let contracts_info_of_nodes (nodes : Ir.node list) : Ir.contracts_info =
  { contract_origin_map = collect_contract_origins nodes; warnings = [] }

let merge_instrumentation_info (left : Stage_info.instrumentation_info)
    (right : Stage_info.instrumentation_info) : Stage_info.instrumentation_info =
  {
    Stage_info.kernel_ir_nodes = left.kernel_ir_nodes @ right.kernel_ir_nodes;
    exported_node_summaries = left.exported_node_summaries @ right.exported_node_summaries;
    raw_ir_nodes = left.raw_ir_nodes @ right.raw_ir_nodes;
    annotated_ir_nodes = left.annotated_ir_nodes @ right.annotated_ir_nodes;
    verified_ir_nodes = left.verified_ir_nodes @ right.verified_ir_nodes;
    kernel_pipeline_lines = left.kernel_pipeline_lines @ right.kernel_pipeline_lines;
    warnings = left.warnings @ right.warnings;
    guarantee_automaton_lines =
      left.guarantee_automaton_lines @ right.guarantee_automaton_lines;
    assume_automaton_lines = left.assume_automaton_lines @ right.assume_automaton_lines;
    guarantee_automaton_tex =
      if left.guarantee_automaton_tex <> "" then left.guarantee_automaton_tex
      else right.guarantee_automaton_tex;
    assume_automaton_tex =
      if left.assume_automaton_tex <> "" then left.assume_automaton_tex
      else right.assume_automaton_tex;
    product_tex = if left.product_tex <> "" then left.product_tex else right.product_tex;
    product_tex_explicit =
      if left.product_tex_explicit <> "" then left.product_tex_explicit else right.product_tex_explicit;
    canonical_tex = if left.canonical_tex <> "" then left.canonical_tex else right.canonical_tex;
    product_lines = left.product_lines @ right.product_lines;
    canonical_lines = left.canonical_lines @ right.canonical_lines;
    obligations_lines = left.obligations_lines @ right.obligations_lines;
    guarantee_automaton_dot =
      if left.guarantee_automaton_dot <> "" then left.guarantee_automaton_dot
      else right.guarantee_automaton_dot;
    assume_automaton_dot =
      if left.assume_automaton_dot <> "" then left.assume_automaton_dot
      else right.assume_automaton_dot;
    product_dot = if left.product_dot <> "" then left.product_dot else right.product_dot;
    product_dot_explicit =
      if left.product_dot_explicit <> "" then left.product_dot_explicit else right.product_dot_explicit;
    canonical_dot = if left.canonical_dot <> "" then left.canonical_dot else right.canonical_dot;
  }

let raw_of_node (node : Ir.node) : (Ir.raw_node, string) result =
  match node.proof_views.raw with
  | Some raw -> Ok raw
  | None ->
      Error
        (Printf.sprintf "IR orchestration: missing raw proof view for node %s"
           node.semantics.sem_nname)

let annotated_of_node (node : Ir.node) : (Ir.annotated_node, string) result =
  match node.proof_views.annotated with
  | Some annotated -> Ok annotated
  | None ->
      Error
        (Printf.sprintf "IR orchestration: missing annotated proof view for node %s"
           node.semantics.sem_nname)

let verified_of_node (node : Ir.node) : (Ir.verified_node, string) result =
  match node.proof_views.verified with
  | Some verified -> Ok verified
  | None ->
      Error
        (Printf.sprintf "IR orchestration: missing verified proof view for node %s"
           node.semantics.sem_nname)

let instrumentation_info_of_node ~(nodes : Ir.node list)
    ~(analyses : (Ast.ident * Product_build.analysis) list) (node : Ir.node) :
    (Stage_info.instrumentation_info, string) result =
  let* analysis = analysis_of_node ~analyses node in
  let* raw_ir = raw_of_node node in
  let* annotated_ir = annotated_of_node node in
  let* verified_ir = verified_of_node node in
  let rendered = Ir_render_product.render ~node_name:node.semantics.sem_nname ~analysis in
  let rendered_canonical =
    Ir_render_canonical.render ~node_name:node.semantics.sem_nname ~analysis ~node
  in
  let kernel_ir =
    Proof_kernel_build.of_node_analysis
      ~node_name:node.semantics.sem_nname
      ~nodes
      ~node
      ~analysis
  in
  let exported_summary =
    Proof_kernel_build.export_node_summary ~node ~normalized_ir:kernel_ir
  in
  Ok
    {
      Stage_info.kernel_ir_nodes = [ kernel_ir ];
      exported_node_summaries = [ exported_summary ];
      raw_ir_nodes = [ raw_ir ];
      annotated_ir_nodes = [ annotated_ir ];
      verified_ir_nodes = [ verified_ir ];
      kernel_pipeline_lines = Ir_render_kernel.render_node_ir kernel_ir;
      warnings = [];
      guarantee_automaton_lines = rendered.guarantee_automaton_lines;
      assume_automaton_lines = rendered.assume_automaton_lines;
      guarantee_automaton_tex = rendered.guarantee_automaton_tex;
      assume_automaton_tex = rendered.assume_automaton_tex;
      product_tex = rendered.product_tex;
      product_tex_explicit = rendered.product_tex_explicit;
      canonical_tex = rendered_canonical.canonical_tex;
      product_lines = rendered.product_lines;
      canonical_lines = rendered_canonical.canonical_lines;
      obligations_lines = rendered.obligations_lines;
      guarantee_automaton_dot = rendered.guarantee_automaton_dot;
      assume_automaton_dot = rendered.assume_automaton_dot;
      product_dot = rendered.product_dot;
      product_dot_explicit = rendered.product_dot_explicit;
      canonical_dot = rendered_canonical.canonical_dot;
    }

let instrumentation_info_of_ir ~(automata : Automata_generation.node_builds) (program : Ir.program)
    : (Stage_info.instrumentation_info, string) result =
  let* analyses = build_analyses ~automata program.nodes in
  program.nodes
  |> List.map (instrumentation_info_of_node ~nodes:program.nodes ~analyses)
  |> Result_utils.all
  |> Result.map
       (List.fold_left merge_instrumentation_info Stage_info.empty_instrumentation_info)

let run (parsed : Stage_types.parsed) (automata : Automata_generation.node_builds) :
    (Ir.program, string) result =
  let initial_ir = From_ast.of_ast_program parsed in
  let* analyses = build_analyses ~automata initial_ir in
  let nodes =
    initial_ir
    |> Post.apply_program ~post_generations:(Post.build_program ~analyses initial_ir)
    |> fun nodes -> Pre.apply_program ~pre_generations:(Pre.build_program ~analyses nodes) nodes
    |> fun nodes ->
    Invariant.apply_program ~invariant_generations:(Invariant.build_program nodes) nodes
    |> Initial.apply_program
    |> Proof_obligation_raw.apply_program
    |> Proof_obligation_annotate.apply_program ~analyses
    |> Proof_obligation_lowering.apply_program
  in
  Ok ({ nodes; contracts_info = contracts_info_of_nodes nodes } : Ir.program)
