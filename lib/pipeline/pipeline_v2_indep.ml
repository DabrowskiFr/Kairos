open Ast

let join_blocks ~sep blocks =
  let b = Buffer.create 4096 in
  List.iteri
    (fun i s ->
      if i > 0 then Buffer.add_string b sep;
      Buffer.add_string b s)
    blocks;
  Buffer.contents b

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
      spans := { Pipeline.start_offset = start_offset; end_offset = !offset } :: !spans)
    blocks;
  (Buffer.contents b, List.rev !spans)

let with_smoke_tests (p : Ast.program) : Ast.program =
  let has_false_ensure (t : Ast.transition) =
    List.exists (fun (f : Ast.fo_o) -> f.value = Ast.LFalse) t.ensures
  in
  let add_transition_smoke (t : Ast.transition) : Ast.transition =
    if has_false_ensure t then t
    else { t with ensures = t.ensures @ [ Ast_provenance.with_origin Ast.Internal Ast.LFalse ] }
  in
  List.map (fun (n : Ast.node) -> { n with trans = List.map add_transition_smoke n.trans }) p

let stage_meta (infos : Pipeline.stage_infos) : (string * (string * string) list) list =
  let p = Option.value ~default:Stage_info.empty_parse_info infos.parse in
  let a = Option.value ~default:Stage_info.empty_automata_info infos.automata_generation in
  let c = Option.value ~default:Stage_info.empty_contracts_info infos.contracts in
  let i = Option.value ~default:Stage_info.empty_instrumentation_info infos.instrumentation in
  [
    ("user", [ ("source_path", Option.value ~default:"" p.source_path); ("warnings", string_of_int (List.length p.warnings)) ]);
    ("automata", [ ("states", string_of_int a.residual_state_count); ("edges", string_of_int a.residual_edge_count) ]);
    ("contracts", [ ("origins", string_of_int (List.length c.contract_origin_map)); ("warnings", string_of_int (List.length c.warnings)) ]);
    ("instrumentation", [ ("atoms", string_of_int i.atom_count); ("obligations_lines", string_of_int (List.length i.obligations_lines)) ]);
  ]

let build_ast_with_info ~input_file () :
    (Pipeline.ast_stages * Pipeline.stage_infos, Pipeline.error) result =
  Provenance.reset ();
  try
    let source, parse_info = Parse_file.parse_source_file_with_info input_file in
    let p_parsed = source.nodes in
    let imported =
      match Modular_imports.load_for_source ~source_path:input_file ~source with
      | Ok imported -> imported
      | Error msg -> raise (Failure msg)
    in
    let local_node_names = List.map (fun (n : Ast.node) -> n.nname) p_parsed in
    let duplicate_import =
      List.find_opt
        (fun (summary : Product_kernel_ir.exported_node_summary_ir) ->
          List.mem summary.signature.node_name local_node_names)
        imported.summaries
    in
    let () =
      match duplicate_import with
      | None -> ()
      | Some summary ->
          failwith
            (Printf.sprintf
               "Imported node '%s' conflicts with a local node in %s"
               summary.signature.node_name input_file)
    in
    let p_automaton, automata, automata_info =
      Middle_end.stage_automata_generation_with_info p_parsed
    in
    let p_monitor, automata, instrumentation_info =
      Middle_end.stage_instrumentation_with_info ~external_summaries:imported.summaries
        (p_automaton, automata)
    in
    let p_contracts, _automata, contracts_info =
      Middle_end.stage_contracts_with_info (p_monitor, automata)
    in
    let asts : Pipeline.ast_stages =
      {
        source;
        parsed = p_parsed;
        automata_generation = p_automaton;
        automata;
        contracts = p_contracts;
        instrumentation = p_monitor;
        imported_summaries = imported.summaries;
      }
    in
    let infos : Pipeline.stage_infos =
      {
        parse = Some parse_info;
        automata_generation = Some automata_info;
        contracts = Some contracts_info;
        instrumentation = Some instrumentation_info;
      }
    in
    Ok (asts, infos)
  with exn -> Error (Pipeline.Stage_error (Printexc.to_string exn))

type ir_nodes = {
  raw_ir_nodes : Kairos_ir.raw_node list;
  annotated_ir_nodes : Kairos_ir.annotated_node list;
  verified_ir_nodes : Kairos_ir.verified_node list;
  kernel_ir_nodes : Product_kernel_ir.node_ir list;
}

let dump_ir_nodes ~input_file : (ir_nodes, Pipeline.error) result =
  match build_ast_with_info ~input_file () with
  | Error _ as e -> e
  | Ok (_asts, infos) ->
      let i = Option.value infos.instrumentation ~default:Stage_info.empty_instrumentation_info in
      Ok {
        raw_ir_nodes = i.raw_ir_nodes;
        annotated_ir_nodes = i.annotated_ir_nodes;
        verified_ir_nodes = i.verified_ir_nodes;
        kernel_ir_nodes = i.kernel_ir_nodes;
      }

let compile_object ~input_file : (Kairos_object.t, Pipeline.error) result =
  match build_ast_with_info ~input_file () with
  | Error _ as err -> err
  | Ok (asts, infos) ->
      let parse_info = Option.value infos.parse ~default:Stage_info.empty_parse_info in
      let instrumentation_info =
        Option.value infos.instrumentation ~default:Stage_info.empty_instrumentation_info
      in
      Kairos_object.build ~source_path:input_file ~source_hash:parse_info.text_hash
        ~imports:(Source_file.imported_paths asts.source) ~program:asts.parsed
        ~runtime_program:asts.instrumentation
        ~kernel_ir_nodes:instrumentation_info.kernel_ir_nodes
      |> Result.map_error (fun msg -> Pipeline.Stage_error msg)

let instrumentation_diag_texts (infos : Pipeline.stage_infos) :
    string * string * string * string * string * string * string * string =
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
    obligations_text,
    String.concat "\n" i.prune_lines,
    i.guarantee_automaton_dot,
    i.assume_automaton_dot,
    i.product_dot )

let program_automaton_texts (asts : Pipeline.ast_stages) : string * string =
  match asts.automata_generation with
  | [] -> ("", "")
  | node :: _ ->
      Product_debug.render_program_automaton ~node_name:node.nname ~node:(Abstract_model.of_ast_node node)

type formula_record = {
  oid : int;
  source : string;
  node : string option;
  transition : string option;
  obligation_kind : string;
  obligation_family : string option;
  obligation_category : string option;
  loc : Ast.loc option;
}

let classify_formula ~(is_require : bool) (f : Ast.fo_o) :
    string * string option * string option =
  let family =
    if is_require then
      match f.origin with
      | Some Coherency -> Some Obligation_taxonomy.FamCoherencyRequires
      | Some Instrumentation -> Some Obligation_taxonomy.FamNoBadRequires
      | Some Compatibility -> Some Obligation_taxonomy.FamMonitorCompatibilityRequires
      | Some AssumeAutomaton -> Some Obligation_taxonomy.FamStateAwareAssumptionRequires
      | Some UserContract | Some Internal | None ->
          Some Obligation_taxonomy.FamTransitionRequires
    else
      match f.origin with
      | Some Coherency -> Some Obligation_taxonomy.FamCoherencyEnsuresShifted
      | Some Instrumentation -> Some Obligation_taxonomy.FamNoBadEnsures
      | Some UserContract | Some Internal | Some Compatibility
      | Some AssumeAutomaton | None ->
          Some Obligation_taxonomy.FamTransitionEnsures
  in
  let family_name = Option.map Obligation_taxonomy.family_name family in
  let category_name =
    match family with
    | None -> None
    | Some fam ->
        Obligation_taxonomy.category_of_family fam |> Option.map Obligation_taxonomy.category_name
  in
  let obligation_kind =
    match family_name with
    | Some name -> name
    | None -> if is_require then "transition_requires" else "transition_ensures"
  in
  (obligation_kind, family_name, category_name)

let build_formula_records (p_obc : Ast.program) : formula_record list =
  let records = ref [] in
  let add record = records := record :: !records in
  List.iter
    (fun (node : Ast.node) ->
      let node_name = node.nname in
      List.iter
        (fun (goal : Ast.fo_o) ->
          add
            {
              oid = goal.oid;
              source = Printf.sprintf "%s: <init>" node_name;
              node = Some node_name;
              transition = None;
              obligation_kind = "initial_coherency_goal";
              obligation_family = Some (Obligation_taxonomy.family_name Obligation_taxonomy.FamInitialCoherencyGoal);
              obligation_category = Some (Obligation_taxonomy.category_name Obligation_taxonomy.CatInitialGoal);
              loc = goal.loc;
            })
        node.attrs.coherency_goals;
      List.iter
        (fun (t : Ast.transition) ->
          let source = Printf.sprintf "%s: %s -> %s" node_name t.src t.dst in
          List.iter
            (fun (req : Ast.fo_o) ->
              let obligation_kind, obligation_family, obligation_category =
                classify_formula ~is_require:true req
              in
              add
                {
                  oid = req.oid;
                  source;
                  node = Some node_name;
                  transition = Some (Printf.sprintf "%s -> %s" t.src t.dst);
                  obligation_kind;
                  obligation_family;
                  obligation_category;
                  loc = req.loc;
                })
            t.requires;
          List.iter
            (fun (ens : Ast.fo_o) ->
              let obligation_kind, obligation_family, obligation_category =
                classify_formula ~is_require:false ens
              in
              add
                {
                  oid = ens.oid;
                  source;
                  node = Some node_name;
                  transition = Some (Printf.sprintf "%s -> %s" t.src t.dst);
                  obligation_kind;
                  obligation_family;
                  obligation_category;
                  loc = ens.loc;
                })
            t.ensures)
        node.trans)
    p_obc;
  List.rev !records

let formula_record_table (records : formula_record list) =
  let tbl = Hashtbl.create (List.length records * 2 + 1) in
  List.iter (fun record -> Hashtbl.replace tbl record.oid record) records;
  tbl

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

let take n xs =
  let rec loop acc n = function
    | _ when n <= 0 -> List.rev acc
    | [] -> List.rev acc
    | x :: rest -> loop (x :: acc) (n - 1) rest
  in
  loop [] n xs

let summarize_instrumented_hypothesis (hyp : Why_prove.sequent_term) =
  let tags =
    let origin_tags = List.map (fun origin -> "origin:" ^ origin) hyp.origin_labels in
    let kind_tags = match hyp.hypothesis_kind with Some kind -> [ "kind:" ^ kind ] | None -> [] in
    let hid_tags = List.map (fun id -> "hid:" ^ string_of_int id) hyp.hypothesis_ids in
    take 4 (origin_tags @ kind_tags @ hid_tags)
  in
  match tags with
  | [] -> hyp.text
  | _ -> Printf.sprintf "[%s] %s" (String.concat ", " tags) hyp.text

let intersect_count xs ys =
  let tbl = Hashtbl.create 16 in
  List.iter (fun x -> Hashtbl.replace tbl x ()) xs;
  List.fold_left (fun acc y -> if Hashtbl.mem tbl y then acc + 1 else acc) 0 ys

let derive_structured_context ~(failing_core : Why_prove.failing_hypothesis_core option)
    (seq : Why_prove.structured_sequent option) =
  match seq with
  | None -> ([], [], [], [], [], [])
  | Some seq ->
      let goal : Why_prove.sequent_term = seq.goal in
      let kept_tbl = Hashtbl.create 16 in
      let removed_tbl = Hashtbl.create 16 in
      (match failing_core with
      | Some core ->
          List.iter (fun id -> Hashtbl.replace kept_tbl id ()) core.kept_hypothesis_ids;
          List.iter (fun id -> Hashtbl.replace removed_tbl id ()) core.removed_hypothesis_ids
      | None -> ());
      let scored =
        seq.hypotheses
        |> List.mapi (fun idx (hyp : Why_prove.sequent_term) ->
               let symbol_overlap = intersect_count goal.symbols hyp.symbols in
               let operator_overlap = intersect_count goal.operators hyp.operators in
               let quantifier_overlap = intersect_count goal.quantifiers hyp.quantifiers in
               let arithmetic_bonus =
                 if goal.has_arithmetic && hyp.has_arithmetic then 1 else 0
               in
               let instrumentation_bonus =
                 if hyp.hypothesis_ids <> [] || hyp.origin_labels <> [] then 3 else 0
               in
               let core_bonus =
                 if List.exists (fun id -> Hashtbl.mem kept_tbl id) hyp.hypothesis_ids then 100 else 0
               in
               let score =
                 (symbol_overlap * 4) + (operator_overlap * 2) + quantifier_overlap
                 + arithmetic_bonus + instrumentation_bonus + core_bonus
               in
               (idx, score, symbol_overlap, hyp))
        |> List.sort (fun (idx_a, score_a, overlap_a, _) (idx_b, score_b, overlap_b, _) ->
               match compare score_b score_a with
               | 0 -> begin
                   match compare overlap_b overlap_a with
                   | 0 -> compare idx_a idx_b
                   | c -> c
                 end
               | c -> c)
      in
      let minimal_context =
        scored
        |> List.filter_map (fun (_idx, score, symbol_overlap, (hyp : Why_prove.sequent_term)) ->
               if score > 0 || symbol_overlap > 0 then Some (summarize_instrumented_hypothesis hyp)
               else None)
        |> take 4
      in
      let broader_context =
        scored
        |> List.filter_map (fun (_idx, score, _symbol_overlap, (hyp : Why_prove.sequent_term)) ->
               if score > 0 then Some (summarize_instrumented_hypothesis hyp) else None)
        |> take 8
      in
      let unused =
        let removed =
          seq.hypotheses
          |> List.filter_map (fun (hyp : Why_prove.sequent_term) ->
                 if List.exists (fun id -> Hashtbl.mem removed_tbl id) hyp.hypothesis_ids then
                   Some (summarize_instrumented_hypothesis hyp)
                 else None)
          |> unique_preserve_order
        in
        if removed <> [] then removed |> take 5
        else
          scored
          |> List.filter_map (fun (_idx, score, symbol_overlap, (hyp : Why_prove.sequent_term)) ->
                 if score = 0 && symbol_overlap = 0 then Some (summarize_instrumented_hypothesis hyp)
                 else None)
          |> take 5
      in
      let minimal_context =
        let replay_context =
          seq.hypotheses
          |> List.filter_map (fun (hyp : Why_prove.sequent_term) ->
                 if List.exists (fun id -> Hashtbl.mem kept_tbl id) hyp.hypothesis_ids then
                   Some (summarize_instrumented_hypothesis hyp)
                 else None)
          |> unique_preserve_order
          |> take 4
        in
        if replay_context <> [] then replay_context else minimal_context
      in
      let kairos_core_hypotheses =
        seq.hypotheses
        |> List.filter_map (fun (hyp : Why_prove.sequent_term) ->
               if hyp.hypothesis_ids <> [] || hyp.origin_labels <> [] then
                 Some (summarize_instrumented_hypothesis hyp)
               else None)
        |> unique_preserve_order
        |> take 6
      in
      let why3_noise_hypotheses =
        seq.hypotheses
        |> List.filter_map (fun (hyp : Why_prove.sequent_term) ->
               if hyp.hypothesis_ids = [] && hyp.origin_labels = [] then
                 Some (summarize_instrumented_hypothesis hyp)
               else None)
        |> unique_preserve_order
        |> take 6
      in
      ( goal.symbols,
        kairos_core_hypotheses,
        why3_noise_hypotheses,
        minimal_context,
        (if broader_context <> [] then broader_context
         else take 6 (List.map summarize_instrumented_hypothesis seq.hypotheses)),
        unused )

let diagnostic_for_trace ~(status : string) ~(record : formula_record option) ~(goal_text : string)
    ~(structured_sequent : Why_prove.structured_sequent option)
    ~(failing_core : Why_prove.failing_hypothesis_core option)
    ~(native_core : Why_prove.native_unsat_core option)
    ~(native_probe : Why_prove.native_solver_probe option) : Pipeline.proof_diagnostic =
  let goal_symbols, kairos_core_hypotheses, why3_noise_hypotheses, relevant_hypotheses,
      context_hypotheses, unused_hypotheses =
    derive_structured_context ~failing_core structured_sequent
  in
  let status_norm = String.lowercase_ascii (String.trim status) in
  let native_probe_status =
    Option.map (fun (probe : Why_prove.native_solver_probe) -> probe.status) native_probe
  in
  let native_probe_detail =
    Option.bind native_probe (fun (probe : Why_prove.native_solver_probe) -> probe.detail)
  in
  let native_probe_model =
    Option.bind native_probe (fun (probe : Why_prove.native_solver_probe) -> probe.model_text)
  in
  let category, probable_cause, missing_elements, suggestions, detail_override =
    match (status_norm, native_probe_status, native_probe_model) with
    | (_, _, Some _) ->
        ( "counterexample_found",
          Some "The native solver produced a satisfying model for the negated VC.",
          [],
          [ "Inspect the native model first: it witnesses a concrete falsification of this obligation.";
            "Compare the model with the Source -> OBC -> Why -> VC chain to identify the missing relation." ],
          Some (Printf.sprintf "Goal `%s` is falsifiable: the native solver returned a concrete model." goal_text) )
    | ("valid" | "proved"), _, _ ->
        ( "proved",
          Some "This VC was discharged successfully.",
          [],
          [ "Use the trace chain to inspect the obligation that was proved." ],
          Some (Printf.sprintf "Goal `%s` was proved successfully." goal_text) )
    | "timeout", _, _ ->
        ( "solver_timeout",
          Some "The solver reached its time limit before closing this VC.",
          [],
          [ "Retry with a larger timeout to separate complexity from a genuine modeling gap.";
            "Inspect the minimal context and the SMT task to identify heavy arithmetic or quantifier interactions." ],
          None )
    | "unknown", _, _ ->
        ( "solver_inconclusive",
          Some
            (match native_probe_detail with
            | Some detail -> Printf.sprintf "The solver returned an inconclusive result on this VC (%s)." detail
            | None -> "The solver returned an inconclusive result on this VC."),
          [],
          [ "Inspect the VC and SMT artefacts for unsupported patterns.";
            "Try strengthening the local invariants or splitting the property into smaller clauses." ],
          None )
    | "invalid", _, _ ->
        ( "counterexample_found",
          Some "The VC is falsifiable: the solver established the negated obligation as satisfiable.",
          [],
          [ "Inspect the native model/counterexample payload first.";
            "Navigate back to Source and OBC to locate the weakest missing relation." ],
          Some (Printf.sprintf "Goal `%s` is falsifiable under the current assumptions." goal_text) )
    | ("failure" | "oom"), _, _ ->
        ( (if native_probe_status = Some "solver_error" then "solver_error" else "solver_failure"),
          Some
            (match native_probe_detail with
            | Some detail -> Printf.sprintf "The prover failed before producing a conclusive proof result (%s)." detail
            | None -> "The prover failed before producing a conclusive proof result."),
          [],
          [ "Inspect the dumped SMT task and prover configuration.";
            "Check that the selected solver/driver matches the generated theory." ],
          None )
    | _ -> (
        match record with
        | Some { obligation_family = Some "no_bad_requires" | Some "no_bad_ensures"; _ } ->
            ( "no_bad_obligation",
              Some "The monitor/product safety obligation leading to bad state exclusion is not discharged.",
              [ "Missing compatibility assumption or monitor support invariant" ],
              [ "Inspect the product automaton and prune reasons around the same transition.";
                "Check whether the monitor instrumentation encodes the expected bad-state exclusion." ],
              None )
        | Some
            {
              obligation_family =
                Some "monitor_compatibility_requires" | Some "state_aware_assumption_requires";
              _;
            } ->
            ( "monitor_product_incompatibility",
              Some "A compatibility-side obligation between the program and monitor automata is not established.",
              [ "Assumption automaton premise"; "monitor/program compatibility invariant" ],
              [ "Inspect the Assume/Guarantee/Product automata around the referenced transition.";
                "Check whether the transition guard and monitor state relation agree." ],
              None )
        | Some { obligation_family = Some "coherency_requires"; _ } ->
            ( "precondition_insufficient",
              Some "The shifted coherency invariant is not available when entering this transition.",
              [ "A stronger incoming invariant or transition precondition" ],
              [ "Inspect the relevant hypotheses to see which state relation is missing.";
                "Strengthen the invariant propagated into this transition." ],
              None )
        | Some { obligation_family = Some "coherency_ensures_shifted"; _ } ->
            ( "invariant_not_preserved",
              Some "The transition body does not preserve the expected shifted invariant.",
              [ "A stronger post-state invariant" ],
              [ "Inspect the minimal context and the Why snippet for the failing preservation step.";
                "Check assignments and monitor updates on this transition." ],
              None )
        | Some { obligation_family = Some "initial_coherency_goal"; _ } ->
            ( "initial_invariant_missing",
              Some "The initial helper goal establishing the base invariant is not proved.",
              [ "An initial-state invariant strong enough for the first step" ],
              [ "Inspect the source initialization and the OBC initial clause.";
                "Check whether the intended base case is encoded explicitly." ],
              None )
        | Some { obligation_family = Some "transition_requires"; _ } ->
            ( "precondition_insufficient",
              Some "The local assumptions available before the transition do not imply the required VC premise.",
              [ "A missing transition precondition or support invariant" ],
              [ "Inspect the relevant hypotheses slice for absent guard/state facts.";
                "If the VC depends on previous-state facts, add an explicit invariant." ],
              None )
        | Some { obligation_family = Some "transition_ensures"; _ } ->
            ( "postcondition_too_strong",
              Some "The generated postcondition is stronger than what the current transition establishes.",
              [ "A stronger transition body invariant or a weaker postcondition" ],
              [ "Inspect the Why and SMT artefacts to see the exact target clause.";
                "Check whether the post-state relation should be split into smaller obligations." ],
              None )
        | _ ->
            ( "proof_failure",
              Some "The VC could not be discharged with the available information.",
              [],
              [ "Inspect the Why, VC and SMT artefacts for the exact clause sent to the solver.";
                "Compare the relevant hypotheses slice with the intended transition invariant." ],
              None ))
  in
  let summary =
    match record with
    | Some record ->
        if kairos_core_hypotheses <> [] then
          Printf.sprintf "%s on %s with %d Kairos hypotheses in the focused core" category
            record.source (List.length kairos_core_hypotheses)
        else if why3_noise_hypotheses <> [] then
          Printf.sprintf "%s on %s; failure is currently dominated by auxiliary Why3 context" category
            record.source
        else Printf.sprintf "%s on %s" category record.source
    | None -> category
  in
  let detail =
    match detail_override with
    | Some detail -> detail
    | None -> (
        match record with
        | Some record ->
            Printf.sprintf "Goal `%s` failed in `%s` (%s)." goal_text record.source record.obligation_kind
        | None -> Printf.sprintf "Goal `%s` failed without a resolved source obligation." goal_text)
  in
  let probable_cause =
    match (probable_cause, kairos_core_hypotheses, why3_noise_hypotheses) with
    | Some _, _ :: _, _ -> probable_cause
    | _, [], _ :: _ ->
        Some
          "The failure currently appears to depend more on auxiliary Why3 context than on an isolated Kairos hypothesis core."
    | _ -> probable_cause
  in
  let suggestions =
    match (native_probe_model, kairos_core_hypotheses, why3_noise_hypotheses) with
    | Some _, _, _ ->
        "Use the native counterexample as the primary debugging entry point before inspecting the broader VC."
        :: suggestions
    | None, _ :: _, _ ->
        "Inspect the instrumented Kairos core first; these hypotheses survived replay-minimization."
        :: suggestions
    | None, [], _ :: _ ->
        "Inspect the Why/VC view: the current failure is dominated by auxiliary Why3 context or solver reasoning."
        :: suggestions
    | _ -> suggestions
  in
  {
    category;
    summary;
    detail;
    probable_cause;
    missing_elements;
    goal_symbols;
    analysis_method =
      (match native_core, failing_core with
      | Some core, _ ->
          Printf.sprintf
            "Native SMT unsat core recovered from %s on hid-named assertions, then remapped to Kairos hypotheses"
            core.solver
      | None, _ when native_probe_model <> None ->
          "Native SMT model recovered from the targeted solver on the focused VC"
      | None, Some _ ->
          "Structured Why3 term analysis with Kairos hypothesis instrumentation plus greedy replay-minimization of failing hid-marked hypotheses"
      | None, None ->
          "Structured Why3 term analysis with Kairos hypothesis instrumentation (origin/hid/kind markers preserved through normalized sequents)");
    solver_detail = native_probe_detail;
    native_unsat_core_solver =
      Option.map (fun (core : Why_prove.native_unsat_core) -> core.solver) native_core;
    native_unsat_core_hypothesis_ids =
      (match native_core with Some core -> core.hypothesis_ids | None -> []);
    native_counterexample_solver =
      Option.bind native_probe (fun (probe : Why_prove.native_solver_probe) ->
          match probe.model_text with Some _ -> Some probe.solver | None -> None);
    native_counterexample_model = native_probe_model;
    kairos_core_hypotheses;
    why3_noise_hypotheses;
    relevant_hypotheses;
    context_hypotheses;
    unused_hypotheses;
    suggestions;
    limitations =
      [ "The minimal context is inferred from normalized Why3 task structure, not from prover unsat cores.";
        "Native counterexample extraction currently relies on a direct Z3 SMT replay path when the targeted VC is satisfiable.";
        "Missing hypotheses are suggested from the goal shape, preserved hypothesis origins and obligation family, not from solver-produced proof objects." ];
  }

let stable_goal_id goal_index why_ids =
  let ids = unique_preserve_order (List.map string_of_int why_ids) in
  match ids with
  | [] -> Printf.sprintf "vc-%03d" (goal_index + 1)
  | _ -> Printf.sprintf "vc-%03d[%s]" (goal_index + 1) (String.concat "-" ids)

let collect_origin_ids why_ids =
  let seen = Hashtbl.create 16 in
  let push acc id =
    if Hashtbl.mem seen id then acc
    else (
      Hashtbl.replace seen id ();
      id :: acc)
  in
  why_ids
  |> List.fold_left
       (fun acc id ->
         let acc = push acc id in
         List.fold_left push acc (Provenance.ancestors id))
       []
  |> List.rev

let resolve_formula_record ~(records : (int, formula_record) Hashtbl.t) ~(why_ids : int list) :
    formula_record option =
  let origin_ids = collect_origin_ids why_ids in
  List.find_map (fun id -> Hashtbl.find_opt records id) origin_ids

let source_from_record_or_state ~(record : formula_record option)
    ~(state_pair : (string * string) option) ~(obc_program : Ast.program) =
  match record with
  | Some record -> record.source
  | None -> (
      match state_pair with
      | None -> ""
      | Some (src_state, dst_state) ->
          List.find_map
            (fun (node : Ast.node) ->
              List.find_map
                (fun (t : Ast.transition) ->
                  if t.src = src_state && t.dst = dst_state then
                    Some (Printf.sprintf "%s: %s -> %s" node.nname t.src t.dst)
                  else None)
                node.trans)
            obc_program
          |> Option.value ~default:(Printf.sprintf "%s -> %s" src_state dst_state))

let lookup_span table id = Hashtbl.find_opt table id

let vc_ids_of_task_goal_ids (task_goal_ids : int list list) : int list =
  List.mapi
    (fun idx ids ->
      if ids = [] then idx + 1
      else
        let vcid = Provenance.fresh_id () in
        Provenance.add_parents ~child:vcid ~parents:ids;
        vcid)
    task_goal_ids

let matches_selected_goal ~(cfg : Pipeline.config) idx =
  match cfg.selected_goal_index with None -> true | Some selected -> idx = selected

let generic_diagnostic_for_status ~(status : string) (diagnostic : Pipeline.proof_diagnostic) :
    Pipeline.proof_diagnostic =
  let normalized = String.lowercase_ascii status in
  match normalized with
  | "valid" | "proved" ->
      {
        diagnostic with
        category = "proved";
        summary = "The goal was proved.";
        detail = "Kairos proved this verification condition on the standard proof path.";
        solver_detail = None;
      }
  | "pending" -> diagnostic
  | "timeout" ->
      {
        diagnostic with
        category = "solver_timeout";
        summary = "The prover timed out on this goal.";
        detail = "Re-run a focused diagnosis on this goal to inspect the Why3/SMT context in detail.";
      }
  | "unknown" ->
      {
        diagnostic with
        category = "solver_inconclusive";
        summary = "The prover returned an inconclusive result.";
        detail = "Re-run a focused diagnosis on this goal to inspect solver feedback and relevant context.";
      }
  | _ ->
      {
        diagnostic with
        category = "solver_failure";
        summary = "The goal failed on the standard proof path.";
        detail = "Run focused diagnosis on this goal to compute replay-based explanations and SMT-level details.";
      }

let apply_goal_results_to_outputs ~(out : Pipeline.outputs)
    ~(goal_results : (int * string * string * float * string option * string * string option) list) :
    Pipeline.outputs =
  let results_tbl = Hashtbl.create (List.length goal_results * 2 + 1) in
  List.iter (fun ((idx, _, _, _, _, _, _) as item) -> Hashtbl.replace results_tbl idx item) goal_results;
  let proof_traces =
    List.map
      (fun (trace : Pipeline.proof_trace) ->
        match Hashtbl.find_opt results_tbl trace.goal_index with
        | None -> trace
        | Some (_idx, goal_name, status, time_s, dump_path, source, vc_id) ->
            {
              trace with
              goal_name;
              status;
              solver_status = status;
              time_s;
              source;
              vc_id;
              dump_path;
              diagnostic = generic_diagnostic_for_status ~status trace.diagnostic;
            })
      out.proof_traces
  in
  let goals =
    List.map
      (fun (trace : Pipeline.proof_trace) ->
        ( trace.goal_name,
          trace.status,
          trace.time_s,
          trace.dump_path,
          trace.source,
          trace.vc_id ))
      proof_traces
  in
  { out with proof_traces; goals }

(* Build exported summaries from the instrumented AST nodes and the kernel IR map.
   This is the bridge between the instrumented Ast.node and the IR-only emission path. *)
let build_program_summaries (p_instrumented : Ast.program)
    (kernel_ir_map : (Ast.ident * Product_kernel_ir.node_ir) list) :
    Product_kernel_ir.exported_node_summary_ir list =
  List.filter_map
    (fun (node : Ast.node) ->
      match List.assoc_opt node.nname kernel_ir_map with
      | None -> None
      | Some normalized_ir ->
          Some (Product_kernel_ir.export_node_summary ~node ~normalized_ir))
    p_instrumented

let build_outputs ~(cfg : Pipeline.config) ~(asts : Pipeline.ast_stages) ~(infos : Pipeline.stage_infos) :
    (Pipeline.outputs, Pipeline.error) result =
  try
    let obligation_summary = Obligation_taxonomy.summarize_program asts.contracts in
    let instrumentation_info =
      Option.value infos.instrumentation ~default:Stage_info.empty_instrumentation_info
    in
    let kernel_ir_map =
      List.map (fun (ir : Product_kernel_ir.node_ir) -> (ir.reactive_program.node_name, ir))
        instrumentation_info.kernel_ir_nodes
    in
    let why_ast =
      match instrumentation_info.verified_ir_nodes with
      | [] ->
          (* Fallback: no verified IR nodes, use the summary-based path. *)
          let program_summaries = build_program_summaries asts.instrumentation kernel_ir_map in
          Emit.compile_program_ast_from_summaries ~prefix_fields:cfg.prefix_fields ~kernel_ir_map
            ~external_summaries:asts.imported_summaries program_summaries
      | verified_nodes ->
          Emit.compile_program_ast_from_verified_nodes ~prefix_fields:cfg.prefix_fields
            ~kernel_ir_map ~external_summaries:asts.imported_summaries verified_nodes
    in
    let why_text, why_spans = Emit.emit_program_ast_with_spans why_ast in
    let why_span_tbl = Hashtbl.create (List.length why_spans * 2 + 1) in
    List.iter
      (fun (wid, (start_offset, end_offset)) ->
        Hashtbl.replace why_span_tbl wid { Pipeline.start_offset = start_offset; end_offset })
      why_spans;
    let vc_tasks = Why_prove.dump_why3_tasks_with_attrs ~text:why_text in
    let vc_text, vc_spans_ordered =
      if cfg.generate_vc_text then join_blocks_with_spans ~sep:"\n(* ---- goal ---- *)\n" vc_tasks else ("", [])
    in
    let smt_tasks = Why_prove.dump_smt2_tasks ~prover:cfg.prover ~text:why_text in
    let smt_text, smt_spans_ordered =
      if cfg.generate_smt_text then join_blocks_with_spans ~sep:"\n; ---- goal ----\n" smt_tasks else ("", [])
    in
    let task_sequents = Why_prove.task_sequents ~text:why_text in
    let task_structured_sequents = Why_prove.task_structured_sequents ~text:why_text in
    let task_goal_wids = Why_prove.task_goal_wids ~text:why_text in
    let task_state_pairs = Why_prove.task_state_pairs ~text:why_text in
    let vc_ids_ordered = vc_ids_of_task_goal_ids task_goal_wids in
    let vc_locs, vc_locs_ordered = Pipeline.build_vcid_locs asts.parsed in
    let vc_loc_tbl = Hashtbl.create (List.length vc_locs * 2 + 1) in
    List.iter (fun (id, loc) -> Hashtbl.replace vc_loc_tbl id loc) vc_locs;
    let formula_records = build_formula_records asts.contracts in
    let formula_record_tbl = formula_record_table formula_records in
    let vc_sources =
      List.mapi
        (fun idx why_ids ->
          let vcid = List.nth vc_ids_ordered idx in
          let record = resolve_formula_record ~records:formula_record_tbl ~why_ids in
          let source =
            source_from_record_or_state ~record
              ~state_pair:(List.nth_opt task_state_pairs idx |> option_join)
              ~obc_program:asts.contracts
          in
          (vcid, source))
        task_goal_wids
      |> List.filter (fun (vcid, _source) ->
             match cfg.selected_goal_index with
             | None -> true
             | Some selected -> List.nth_opt vc_ids_ordered selected = Some vcid)
    in
    let dot_text, labels_text =
      if cfg.generate_monitor_text then Dot_emit.dot_monitor_program ~show_labels:false asts.automata_generation
      else ("", "")
    in
    let dot_png, dot_png_error =
      if cfg.generate_dot_png && dot_text <> "" then Pipeline.dot_png_from_text_diagnostic dot_text
      else (None, None)
    in
    let program_dot, program_automaton_text = program_automaton_texts asts in
    let guarantee_automaton_text, assume_automaton_text, product_text, obligations_map_text_raw,
        prune_reasons_text, guarantee_automaton_dot, assume_automaton_dot, product_dot =
      instrumentation_diag_texts infos
    in
    let program_png, program_png_error =
      if String.trim program_dot = "" then (None, Some "Program automaton DOT is empty.")
      else Pipeline.dot_png_from_text_diagnostic program_dot
    in
    let guarantee_automaton_png, guarantee_automaton_png_error =
      if String.trim guarantee_automaton_dot = "" then
        (None, Some "Guarantee automaton DOT is empty.")
      else Pipeline.dot_png_from_text_diagnostic guarantee_automaton_dot
    in
    let assume_automaton_png, assume_automaton_png_error =
      if String.trim assume_automaton_dot = "" then
        (None, Some "Assume automaton DOT is empty.")
      else Pipeline.dot_png_from_text_diagnostic assume_automaton_dot
    in
    let product_png, product_png_error =
      if String.trim product_dot = "" then (None, Some "Product automaton DOT is empty.")
      else Pipeline.dot_png_from_text_diagnostic product_dot
    in
    let obligations_map_text =
      let taxonomy_text = Obligation_taxonomy.render_summary obligation_summary in
      if String.trim obligations_map_text_raw = "" then
        "-- OBC obligation taxonomy --\n" ^ taxonomy_text
      else
        obligations_map_text_raw ^ "\n\n-- OBC obligation taxonomy --\n" ^ taxonomy_text
    in
    let goal_results =
      if cfg.prove && not cfg.wp_only then
        let finished = ref [] in
        let _summary, _ =
          Why_prove.prove_text_detailed_with_callbacks ~timeout:cfg.timeout_s ~prover:cfg.prover
            ?prover_cmd:cfg.prover_cmd ?selected_goal_index:cfg.selected_goal_index ~text:why_text
            ~vc_ids_ordered:(Some vc_ids_ordered)
            ~should_cancel:(fun () -> false)
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
            let stable_id = stable_goal_id idx why_ids in
            (idx, stable_id, "pending", 0.0, None, "", Some (string_of_int vcid)))
          task_goal_wids
        |> List.filter (fun (idx, _, _, _, _, _, _) -> matches_selected_goal ~cfg idx)
    in
    let goal_result_tbl = Hashtbl.create (List.length goal_results * 2 + 1) in
    List.iter
      (fun ((idx, _, _, _, _, _, _) as goal_result) -> Hashtbl.replace goal_result_tbl idx goal_result)
      goal_results;
    let proof_traces =
      List.mapi (fun idx why_ids -> (idx, why_ids)) task_goal_wids
      |> List.filter_map (fun (idx, why_ids) ->
             if not (matches_selected_goal ~cfg idx) then None
             else
          let origin_ids = collect_origin_ids why_ids in
          let record = resolve_formula_record ~records:formula_record_tbl ~why_ids in
          let source =
            source_from_record_or_state ~record
              ~state_pair:(List.nth_opt task_state_pairs idx |> option_join)
              ~obc_program:asts.contracts
          in
          let _goal_idx, goal_name, status, time_s, dump_path, _raw_source, raw_vcid =
            match Hashtbl.find_opt goal_result_tbl idx with
            | Some goal -> goal
            | None ->
                let fallback_id = stable_goal_id idx why_ids in
                (idx, fallback_id, "pending", 0.0, None, source, Some (string_of_int (List.nth vc_ids_ordered idx)))
          in
          let stable_id = stable_goal_id idx why_ids in
          let native_core, native_probe, failing_core =
            if not cfg.compute_proof_diagnostics then (None, None, None)
            else
              match String.lowercase_ascii status with
              | "valid" | "proved" ->
                  if cfg.selected_goal_index = Some idx then
                    ( Why_prove.native_unsat_core_for_goal ~timeout:cfg.timeout_s ~prover:cfg.prover
                        ~text:why_text ~goal_index:idx (),
                      None,
                      None )
                  else (None, None, None)
              | "pending" -> (None, None, None)
              | _ ->
                  let native_probe =
                    Why_prove.native_solver_probe_for_goal ~timeout:cfg.timeout_s ~prover:cfg.prover
                      ~text:why_text ~goal_index:idx ()
                  in
                  let failing_core =
                    match native_probe with
                    | Some { model_text = Some _; _ } -> None
                    | _ ->
                        Why_prove.minimize_failing_hypotheses ~timeout:1 ?prover_cmd:cfg.prover_cmd
                          ~prover:cfg.prover ~text:why_text ~goal_index:idx ()
                  in
                  (None, native_probe, failing_core)
          in
          let diagnostic =
            diagnostic_for_trace ~status ~record ~goal_text:goal_name
              ~structured_sequent:(List.nth_opt task_structured_sequents idx)
              ~failing_core
              ~native_core
              ~native_probe
          in
          let source_span =
            match List.find_map (fun id -> Hashtbl.find_opt vc_loc_tbl id) origin_ids with
            | Some _ as loc -> loc
            | None -> Option.bind record (fun r -> r.loc)
          in
          Some
            {
            Pipeline.goal_index = idx;
            stable_id;
            goal_name;
            status;
            solver_status =
              (match native_probe with Some probe -> probe.status | None -> status);
            time_s;
            source;
            node = Option.bind record (fun r -> r.node);
            transition = Option.bind record (fun r -> r.transition);
            obligation_kind =
              (match record with Some r -> r.obligation_kind | None -> "unknown");
            obligation_family = Option.bind record (fun r -> r.obligation_family);
            obligation_category = Option.bind record (fun r -> r.obligation_category);
            origin_ids;
            vc_id = raw_vcid;
            source_span;
            why_span =
              List.find_map (fun id -> lookup_span why_span_tbl id) origin_ids;
            vc_span = List.nth_opt vc_spans_ordered idx;
            smt_span = List.nth_opt smt_spans_ordered idx;
            dump_path;
            diagnostic;
            })
    in
    let goals =
      List.map
        (fun (trace : Pipeline.proof_trace) ->
          ( trace.goal_name,
            trace.status,
            trace.time_s,
            trace.dump_path,
            trace.source,
            trace.vc_id ))
        proof_traces
    in
    Ok
      {
        Pipeline.why_text;
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
        proof_traces;
        vc_sources;
        task_sequents;
        vc_locs;
        vc_locs_ordered;
        vc_spans_ordered =
          List.map
            (fun (span : Pipeline.text_span) -> (span.start_offset, span.end_offset))
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
          |> List.concat_map Product_kernel_ir.render_historical_clauses
          |> String.concat "\n";
        eliminated_clauses_text =
          instrumentation_info.kernel_ir_nodes
          |> List.concat_map Product_kernel_ir.render_eliminated_clauses
          |> String.concat "\n";
      }
  with exn -> Error (Pipeline.Stage_error (Printexc.to_string exn))

let instrumentation_pass ~generate_png ~input_file =
  match build_ast_with_info ~input_file () with
  | Error _ as e -> e
  | Ok (asts, infos) ->
      let obligation_summary = Obligation_taxonomy.summarize_program asts.contracts in
      let instrumentation_info =
        Option.value infos.instrumentation ~default:Stage_info.empty_instrumentation_info
      in
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
      let dot_png, dot_png_error =
        if generate_png then Pipeline.dot_png_from_text_diagnostic dot_text else (None, None)
      in
      let program_png, program_png_error =
        if String.trim program_dot = "" then (None, Some "Program automaton DOT is empty.")
        else Pipeline.dot_png_from_text_diagnostic program_dot
      in
      let guarantee_automaton_png, guarantee_automaton_png_error =
        if String.trim guarantee_automaton_dot = "" then
          (None, Some "Guarantee automaton DOT is empty.")
        else Pipeline.dot_png_from_text_diagnostic guarantee_automaton_dot
      in
      let assume_automaton_png, assume_automaton_png_error =
        if String.trim assume_automaton_dot = "" then
          (None, Some "Assume automaton DOT is empty.")
        else Pipeline.dot_png_from_text_diagnostic assume_automaton_dot
      in
      let product_png, product_png_error =
        if String.trim product_dot = "" then (None, Some "Product automaton DOT is empty.")
        else Pipeline.dot_png_from_text_diagnostic product_dot
      in
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
            |> List.concat_map Product_kernel_ir.render_historical_clauses
            |> String.concat "\n";
          eliminated_clauses_text =
            instrumentation_info.kernel_ir_nodes
            |> List.concat_map Product_kernel_ir.render_eliminated_clauses
            |> String.concat "\n";
        }

let why_pass ~prefix_fields ~input_file =
  match build_ast_with_info ~input_file () with
  | Error _ as e -> e
  | Ok (asts, infos) ->
      let instrumentation_info =
        Option.value infos.instrumentation ~default:Stage_info.empty_instrumentation_info
      in
      let kernel_ir_map =
        List.map (fun (ir : Product_kernel_ir.node_ir) -> (ir.reactive_program.node_name, ir))
          instrumentation_info.kernel_ir_nodes
      in
      let program_summaries = build_program_summaries asts.instrumentation kernel_ir_map in
      let why_ast =
        Emit.compile_program_ast_from_summaries ~prefix_fields ~kernel_ir_map
          ~external_summaries:asts.imported_summaries program_summaries
      in
      let why_text = Emit.emit_program_ast why_ast in
      Ok { Pipeline.why_text = why_text; stage_meta = stage_meta infos }

let obligations_pass ~prefix_fields ~prover ~input_file =
  match build_ast_with_info ~input_file () with
  | Error _ as e -> e
  | Ok (asts, infos) ->
      let instrumentation_info =
        Option.value infos.instrumentation ~default:Stage_info.empty_instrumentation_info
      in
      let kernel_ir_map =
        List.map (fun (ir : Product_kernel_ir.node_ir) -> (ir.reactive_program.node_name, ir))
          instrumentation_info.kernel_ir_nodes
      in
      let program_summaries = build_program_summaries asts.instrumentation kernel_ir_map in
      let why_ast =
        Emit.compile_program_ast_from_summaries ~prefix_fields ~kernel_ir_map
          ~external_summaries:asts.imported_summaries program_summaries
      in
      let why_text = Emit.emit_program_ast why_ast in
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
  if cfg.compute_proof_diagnostics then
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
  else
    match build_ast_with_info ~input_file:cfg.input_file () with
    | Error _ as e -> e
    | Ok (asts, infos) ->
        let pending_cfg =
          { cfg with prove = false; compute_proof_diagnostics = false }
        in
        (match build_outputs ~cfg:pending_cfg ~asts ~infos with
        | Error _ as e -> e
        | Ok pending_out ->
            on_outputs_ready { pending_out with goals = [] };
            let goal_names = List.map (fun (g, _, _, _, _, _) -> g) pending_out.goals in
            on_goals_ready (goal_names, pending_out.vc_ids_ordered);
            if not cfg.prove || cfg.wp_only then Ok pending_out
            else
              let finished = ref [] in
              let _summary, _ =
                Why_prove.prove_text_detailed_with_callbacks ~timeout:cfg.timeout_s ~prover:cfg.prover
                  ?prover_cmd:cfg.prover_cmd ?selected_goal_index:cfg.selected_goal_index
                  ~text:pending_out.why_text ~vc_ids_ordered:(Some pending_out.vc_ids_ordered)
                  ~should_cancel
                  ~on_goal_start:(fun _ _ -> ())
                  ~on_goal_done:(fun idx goal status time_s dump_path source vcid ->
                    finished := (idx, goal, status, time_s, dump_path, source, vcid) :: !finished;
                    on_goal_done idx goal status time_s dump_path source vcid)
                  ()
              in
              if should_cancel () then Error (Pipeline.Stage_error "Request cancelled")
              else
                let goal_results =
                  List.sort
                    (fun (a, _, _, _, _, _, _) (b, _, _, _, _, _, _) -> compare a b)
                    !finished
                in
                Ok (apply_goal_results_to_outputs ~out:pending_out ~goal_results))
