open Ast
open Support
open Fo_specs
open Collect

module Abs = Normalized_program
module PT = Product_types
open Proof_kernel_types

let build_source_summary_clauses ~(node : Abs.node) ~(analysis : Product_build.analysis)
    ~(steps : product_step_ir list) ~automaton_guard_fo : generated_clause_ir list =
  let _analysis = analysis in
  let current (desc : clause_fact_desc_ir) : clause_fact_ir = { time = CurrentTick; desc } in
  let input_names =
    node.semantics.sem_inputs |> List.map (fun (v : Ast.vdecl) -> v.vname) |> List.sort_uniq String.compare
  in
  let rec iexpr_mentions_current_input (e : Ast.iexpr) =
    match e.iexpr with
    | IVar name -> List.mem name input_names
    | ILitInt _ | ILitBool _ -> false
    | IPar inner | IUn (_, inner) -> iexpr_mentions_current_input inner
    | IBin (_, a, b) -> iexpr_mentions_current_input a || iexpr_mentions_current_input b
  in
  let hexpr_mentions_current_input = function
    | HNow e -> iexpr_mentions_current_input e
    | HPreK _ -> false
  in
  let rec fo_mentions_current_input (f : Ast.ltl) =
    match f with
    | LTrue | LFalse -> false
    | LAtom (FRel (a, _, b)) -> hexpr_mentions_current_input a || hexpr_mentions_current_input b
    | LAtom (FPred (_, hs)) -> List.exists hexpr_mentions_current_input hs
    | LNot inner | LX inner | LG inner -> fo_mentions_current_input inner
    | LAnd (a, b) | LOr (a, b) | LImp (a, b) | LW (a, b) ->
        fo_mentions_current_input a || fo_mentions_current_input b
  in
  let rec normalize_source_summary (f : ltl) : ltl =
    match f with
    | LNot (LOr (LNot a, LNot b)) -> LAnd (normalize_source_summary a, normalize_source_summary b)
    | LNot inner -> begin
        match normalize_source_summary inner with
        | LTrue -> LFalse
        | LFalse -> LTrue
        | inner -> LNot inner
      end
    | LAnd (a, b) -> begin
        match (normalize_source_summary a, normalize_source_summary b) with
        | LFalse, _ | _, LFalse -> LFalse
        | LTrue, rhs -> rhs
        | lhs, LTrue -> lhs
        | lhs, rhs -> LAnd (lhs, rhs)
      end
    | LOr (a, b) -> begin
        match (normalize_source_summary a, normalize_source_summary b) with
        | LTrue, _ | _, LTrue -> LTrue
        | LFalse, rhs -> rhs
        | lhs, LFalse -> lhs
        | lhs, rhs -> LOr (lhs, rhs)
      end
    | LImp (a, b) -> LImp (normalize_source_summary a, normalize_source_summary b)
    | LTrue | LFalse | LAtom _ | LX _ | LG _ | LW _ -> f
  in
  let term_or a b = normalize_source_summary (LOr (a, b)) in
  let term_and a b = normalize_source_summary (LAnd (a, b)) in
  let term_not a = normalize_source_summary (LNot a) in
  let rec phase_summary_obviously_inconsistent (f : ltl) : bool =
    match normalize_source_summary f with
    | LFalse -> true
    | LAtom (FRel (HNow { iexpr = IVar x; _ }, RNeq, HNow { iexpr = IVar y; _ })) when String.equal x y -> true
    | LNot (LAtom (FRel (HNow { iexpr = IVar x; _ }, REq, HNow { iexpr = IVar y; _ }))) when String.equal x y ->
        true
    | LNot LTrue -> true
    | LAnd (a, b) -> phase_summary_obviously_inconsistent a || phase_summary_obviously_inconsistent b
    | _ -> false
  in
  let same_product_state (a : product_state_ir) (b : product_state_ir) =
    a.prog_state = b.prog_state
    && a.assume_state_index = b.assume_state_index
    && a.guarantee_state_index = b.guarantee_state_index
  in
  let dst_states =
    steps
    |> List.filter_map (fun (step : product_step_ir) ->
           match step.step_kind with
           | StepSafe -> Some step.dst
           | StepBadGuarantee | StepBadAssumption -> None)
    |> List.sort_uniq Stdlib.compare
  in
  let incoming_summaries =
    dst_states
    |> List.filter_map (fun (dst : product_state_ir) ->
         let safe_cases =
           steps
           |> List.filter (fun step -> same_product_state step.dst dst && step.step_kind = StepSafe)
           |> List.map (fun step -> step.guarantee_edge.guard)
           |> List.filter (fun fo -> not (fo_mentions_current_input fo))
           |> List.sort_uniq Stdlib.compare
         in
         let safe_cases =
           if String.equal dst.prog_state node.semantics.sem_init_state then
             LTrue :: safe_cases |> List.sort_uniq Stdlib.compare
           else safe_cases
         in
         match safe_cases with
         | [] -> None
         | safe_case :: rest ->
             let pre_invariant =
               List.fold_left (fun acc fo -> LOr (acc, fo)) safe_case rest
               |> normalize_source_summary
             in
             if phase_summary_obviously_inconsistent pre_invariant then None
             else
               Some
                 ({
                   origin = OriginSourceProductSummary;
                   anchor = ClauseAnchorProductState dst;
                   hypotheses =
                     [
                       current (FactProgramState dst.prog_state);
                       current (FactGuaranteeState dst.guarantee_state_index);
                     ];
                   conclusions =
                     [ current (FactPhaseFormula pre_invariant); current (FactFormula pre_invariant) ];
                 } : generated_clause_ir))
  in
  let summarized_states =
    incoming_summaries
    |> List.filter_map (fun (clause : generated_clause_ir) ->
           match clause.anchor with
           | ClauseAnchorProductState st -> Some st
           | ClauseAnchorProductStep _ -> None)
    |> List.sort_uniq Stdlib.compare
  in
  let all_states =
    steps
    |> List.concat_map (fun (step : product_step_ir) -> [ step.src; step.dst ])
    |> List.sort_uniq Stdlib.compare
  in
  let outgoing_safe_summary_for_gstate gidx =
    analysis.guarantee_grouped_edges
    |> List.filter_map (fun ((src, guard_raw, dst) : PT.automaton_edge) ->
           if src = gidx && (analysis.guarantee_bad_idx < 0 || dst <> analysis.guarantee_bad_idx)
           then Some (automaton_guard_fo analysis.guarantee_atom_map_exprs guard_raw)
           else None)
    |> List.sort_uniq Stdlib.compare
    |> function
    | [] -> None
    | guard :: guards ->
        Some
          (List.fold_left (fun acc fo -> LOr (acc, fo)) guard guards
          |> normalize_source_summary)
  in
  let fallback_summaries =
    all_states
    |> List.filter (fun st -> not (List.mem st summarized_states))
    |> List.filter_map (fun (st : product_state_ir) ->
           match outgoing_safe_summary_for_gstate st.guarantee_state_index with
           | None -> None
           | Some phase_formula ->
               if phase_summary_obviously_inconsistent phase_formula then None
               else
                 Some
                   ({
                     origin = OriginSourceProductSummary;
                     anchor = ClauseAnchorProductState st;
                     hypotheses =
                       [
                         current (FactProgramState st.prog_state);
                         current (FactGuaranteeState st.guarantee_state_index);
                       ];
                     conclusions =
                       [ current (FactPhaseFormula phase_formula); current (FactFormula phase_formula) ];
                   } : generated_clause_ir))
  in
  let raw_summaries = incoming_summaries @ fallback_summaries in
  let phase_formula_of_clause (clause : generated_clause_ir) =
    clause.conclusions
    |> List.find_map (fun (fact : clause_fact_ir) ->
           match (fact.time, fact.desc) with
           | CurrentTick, FactPhaseFormula fo -> Some fo
           | _ -> None)
  in
  let anchor_state_of_clause (clause : generated_clause_ir) =
    match clause.anchor with
    | ClauseAnchorProductState st -> Some st
    | ClauseAnchorProductStep _ -> None
  in
  let raw_formula_table = Hashtbl.create 16 in
  List.iter
    (fun (clause : generated_clause_ir) ->
      match (anchor_state_of_clause clause, phase_formula_of_clause clause) with
      | Some st, Some fo ->
          let key = (st.prog_state, st.guarantee_state_index) in
          let merged =
            match Hashtbl.find_opt raw_formula_table key with
            | None -> fo
            | Some prev -> term_or prev fo
          in
          Hashtbl.replace raw_formula_table key merged
      | _ -> ())
    raw_summaries;
  let by_prog_state = Hashtbl.create 16 in
  Hashtbl.iter
    (fun ((prog_state, gidx) as key) fo ->
      let prev = Hashtbl.find_opt by_prog_state prog_state |> Option.value ~default:[] in
      Hashtbl.replace by_prog_state prog_state ((gidx, fo, key) :: prev))
    raw_formula_table;
  let exclusive_formula_table = Hashtbl.create 16 in
  Hashtbl.iter
    (fun _prog_state entries ->
      let entries = List.sort (fun (g1, _, _) (g2, _, _) -> Int.compare g1 g2) entries in
      let _covered, () =
        List.fold_left
          (fun (covered_opt, ()) (_gidx, raw_fo, key) ->
            let exclusive =
              match covered_opt with
              | None -> raw_fo
              | Some covered -> term_and raw_fo (term_not covered)
            in
            Hashtbl.replace exclusive_formula_table key (normalize_source_summary exclusive);
            let covered_opt =
              match covered_opt with
              | None -> Some raw_fo
              | Some covered -> Some (term_or covered raw_fo)
            in
            (covered_opt, ()))
          (None, ()) entries
      in
      ())
    by_prog_state;
  raw_summaries
  |> List.map (fun (clause : generated_clause_ir) ->
         match anchor_state_of_clause clause with
         | None -> clause
         | Some st ->
             let key = (st.prog_state, st.guarantee_state_index) in
             match Hashtbl.find_opt exclusive_formula_table key with
             | Some phase_formula when not (phase_summary_obviously_inconsistent phase_formula) ->
                 {
                   clause with
                   conclusions =
                     [ current (FactPhaseFormula phase_formula); current (FactFormula phase_formula) ];
                 }
             | _ -> clause)

let build_generated_clauses ~(node : Abs.node) ~(analysis : Product_build.analysis)
    ~(initial_state : product_state_ir) ~(steps : product_step_ir list) ~automaton_guard_fo
    ~is_live_state : generated_clause_ir list =
  let current (desc : clause_fact_desc_ir) : clause_fact_ir = { time = CurrentTick; desc } in
  let previous (desc : clause_fact_desc_ir) : clause_fact_ir = { time = PreviousTick; desc } in
  let step_ctx (desc : clause_fact_desc_ir) : clause_fact_ir = { time = StepTickContext; desc } in
  let rec split_top_level_or (f : ltl) : ltl list =
    match f with
    | LOr (a, b) -> split_top_level_or a @ split_top_level_or b
    | _ -> [ f ]
  in
  let rec normalize_phase_summary (f : ltl) : ltl =
    match f with
    | LNot (LOr (LNot a, LNot b)) -> LAnd (normalize_phase_summary a, normalize_phase_summary b)
    | LNot inner -> LNot (normalize_phase_summary inner)
    | LAnd (a, b) -> LAnd (normalize_phase_summary a, normalize_phase_summary b)
    | LOr (a, b) -> LOr (normalize_phase_summary a, normalize_phase_summary b)
    | LImp (a, b) -> LImp (normalize_phase_summary a, normalize_phase_summary b)
    | LTrue | LFalse | LAtom _ | LX _ | LG _ | LW _ -> f
  in
  let same_product_state (a : product_state_ir) (b : product_state_ir) =
    a.prog_state = b.prog_state
    && a.assume_state_index = b.assume_state_index
    && a.guarantee_state_index = b.guarantee_state_index
  in
  let phase_formula_for_dst (dst : product_state_ir) =
    let safe_cases =
      steps
      |> List.filter (fun step -> same_product_state step.dst dst && step.step_kind = StepSafe)
      |> List.map (fun step -> step.guarantee_edge.guard)
      |> List.sort_uniq Stdlib.compare
    in
    match safe_cases with
    | [] -> None
    | safe_case :: rest ->
        Some (List.fold_left (fun acc fo -> LOr (acc, fo)) safe_case rest |> normalize_phase_summary)
  in
  let invariants_for_state state_name =
    List.filter_map
      (fun inv ->
        if (inv.is_eq && inv.state = state_name) || ((not inv.is_eq) && inv.state <> state_name) then
          Some (current (FactFormula inv.formula))
        else None)
      node.specification.spec_invariants_state_rel
  in
  let init_clauses =
    [
      ({
        origin = OriginInitNodeInvariant;
        anchor = ClauseAnchorProductState initial_state;
        hypotheses = [ current (FactProgramState initial_state.prog_state) ];
        conclusions = current (FactProgramState initial_state.prog_state) :: invariants_for_state initial_state.prog_state;
      } : generated_clause_ir);
      ({
        origin = OriginInitAutomatonCoherence;
        anchor = ClauseAnchorProductState initial_state;
        hypotheses = [ current (FactProgramState initial_state.prog_state) ];
        conclusions = [ current (FactGuaranteeState initial_state.guarantee_state_index) ];
      } : generated_clause_ir);
    ]
  in
  let source_summary_clauses =
    build_source_summary_clauses ~node ~analysis ~steps ~automaton_guard_fo
  in
  let step_clauses =
    List.concat_map
      (fun step ->
        let src_live =
          is_live_state ~analysis
            {
              PT.prog_state = step.src.prog_state;
              assume_state = step.src.assume_state_index;
              guarantee_state = step.src.guarantee_state_index;
            }
        in
        let propagation =
          if src_live then
            let base_hypotheses =
              [
                previous (FactProgramState step.src.prog_state);
                previous (FactGuaranteeState step.src.guarantee_state_index);
                step_ctx (FactFormula step.program_guard);
                step_ctx (FactFormula step.assume_edge.guard);
              ]
            in
            let phase_clause =
              [
                ({
                  origin = OriginPhaseStepSummary;
                  anchor = ClauseAnchorProductStep step;
                  hypotheses = base_hypotheses;
                  conclusions = [ current (FactPhaseFormula step.guarantee_edge.guard) ];
                } : generated_clause_ir);
              ]
            in
            let phase_pre_clause =
              match phase_formula_for_dst step.src with
              | None -> []
              | Some phase_formula ->
                  [
                    ({
                      origin = OriginPhaseStepPreSummary;
                      anchor = ClauseAnchorProductStep step;
                      hypotheses =
                        [
                          previous (FactProgramState step.src.prog_state);
                          previous (FactGuaranteeState step.src.guarantee_state_index);
                        ];
                      conclusions = [ previous (FactPhaseFormula phase_formula) ];
                    } : generated_clause_ir);
                  ]
            in
            [
              ({
                origin = OriginPropagationNodeInvariant;
                anchor = ClauseAnchorProductStep step;
                hypotheses = base_hypotheses;
                conclusions = current (FactProgramState step.dst.prog_state) :: invariants_for_state step.dst.prog_state;
              } : generated_clause_ir);
              ({
                origin = OriginPropagationAutomatonCoherence;
                anchor = ClauseAnchorProductStep step;
                hypotheses = base_hypotheses;
                conclusions = [ current (FactGuaranteeState step.dst.guarantee_state_index) ];
              } : generated_clause_ir);
            ]
            @ phase_pre_clause @ phase_clause
          else []
        in
        let safety =
          match step.step_kind with
          | StepBadGuarantee ->
              split_top_level_or step.guarantee_edge.guard
              |> List.map (fun bad_case ->
                     ({
                       origin = OriginSafety;
                       anchor = ClauseAnchorProductStep step;
                       hypotheses =
                         [
                           previous (FactProgramState step.src.prog_state);
                           previous (FactGuaranteeState step.src.guarantee_state_index);
                           step_ctx (FactFormula step.program_guard);
                           step_ctx (FactFormula step.assume_edge.guard);
                           step_ctx (FactFormula bad_case);
                         ];
                       conclusions = [ current FactFalse ];
                     } : generated_clause_ir))
          | StepSafe | StepBadAssumption -> []
        in
        propagation @ safety)
      steps
  in
  init_clauses @ source_summary_clauses @ step_clauses

let lower_clause_fact ~(pre_k_map : (Ast.hexpr * Support.pre_k_info) list) (fact : clause_fact_ir) :
    clause_fact_ir option =
  let temporal_bindings = temporal_bindings_of_pre_k_map ~pre_k_map in
  let lower_desc = function
    | FactProgramState _ as desc -> Some desc
    | FactGuaranteeState _ as desc -> Some desc
    | FactPhaseFormula fo ->
        Option.map (fun fo' -> FactPhaseFormula fo') (lower_ltl_temporal_bindings ~temporal_bindings fo)
    | FactFalse -> Some FactFalse
    | FactFormula fo ->
        Option.map (fun fo' -> FactFormula fo') (lower_ltl_temporal_bindings ~temporal_bindings fo)
  in
  Option.map (fun desc -> { fact with desc }) (lower_desc fact.desc)

let lower_generated_clause ~(pre_k_map : (Ast.hexpr * Support.pre_k_info) list)
    (clause : generated_clause_ir) : generated_clause_ir option =
  let rec lower_all acc = function
    | [] -> Some (List.rev acc)
    | fact :: tl -> (
        match lower_clause_fact ~pre_k_map fact with
        | None -> None
        | Some fact' -> lower_all (fact' :: acc) tl)
  in
  match (lower_all [] clause.hypotheses, lower_all [] clause.conclusions) with
  | Some hypotheses, Some conclusions ->
      if List.exists (fun (fact : clause_fact_ir) -> fact.desc = FactFormula LFalse || fact.desc = FactFalse) hypotheses
      then None
      else Some { clause with hypotheses; conclusions }
  | _ -> None

let relationalize_clause_fact ~(pre_k_map : (Ast.hexpr * Support.pre_k_info) list)
    (fact : clause_fact_ir) : relational_clause_fact_ir option =
  let temporal_bindings = temporal_bindings_of_pre_k_map ~pre_k_map in
  let rel_desc = function
    | FactProgramState st -> Some (RelFactProgramState st)
    | FactGuaranteeState idx -> Some (RelFactGuaranteeState idx)
    | FactPhaseFormula fo ->
        Option.map (fun fo' -> RelFactPhaseFormula fo') (lower_ltl_temporal_bindings ~temporal_bindings fo)
    | FactFormula fo ->
        Option.map (fun fo' -> RelFactFormula fo') (lower_ltl_temporal_bindings ~temporal_bindings fo)
    | FactFalse -> Some RelFactFalse
  in
  Option.map (fun desc -> { time = fact.time; desc }) (rel_desc fact.desc)

let expand_relational_hypotheses (facts : relational_clause_fact_ir list) :
    relational_clause_fact_ir list list =
  let rec expand_one acc = function
    | [] -> [ List.rev acc ]
    | ({ desc = RelFactFormula (LOr (a, b)); _ } as fact) :: tl ->
        let left = { fact with desc = RelFactFormula (Fo_simplifier.simplify_fo a) } in
        let right = { fact with desc = RelFactFormula (Fo_simplifier.simplify_fo b) } in
        (expand_one (left :: acc) tl) @ expand_one (right :: acc) tl
    | fact :: tl -> expand_one (fact :: acc) tl
  in
  expand_one [] facts

let normalize_relational_hypotheses (facts : relational_clause_fact_ir list) :
    relational_clause_fact_ir list option =
  let combine_formula left right =
    match (left, right) with
    | RelFactFormula a, RelFactFormula b -> Some (RelFactFormula (Fo_simplifier.simplify_fo (LAnd (a, b))))
    | _ -> None
  in
  let rec insert acc fact =
    match acc with
    | [] -> Some [ fact ]
    | hd :: tl ->
        if hd.time = fact.time then
          match combine_formula hd.desc fact.desc with
          | Some (RelFactFormula LFalse) -> None
          | Some desc -> Some ({ hd with desc } :: tl)
          | None -> Option.map (fun tl' -> hd :: tl') (insert tl fact)
        else
          Option.map (fun tl' -> hd :: tl') (insert tl fact)
  in
  let rec fold acc = function
    | [] ->
        Some
          (List.filter (fun (fact : relational_clause_fact_ir) -> fact.desc <> RelFactFormula LTrue) acc)
    | ({ desc = RelFactFormula LFalse; _ } : relational_clause_fact_ir) :: _ -> None
    | ({ desc = RelFactFalse; _ } : relational_clause_fact_ir) :: _ -> None
    | fact :: tl -> (
        match insert acc fact with
        | None -> None
        | Some acc' -> fold acc' tl)
  in
  fold [] facts

let relationalize_generated_clause ~(pre_k_map : (Ast.hexpr * Support.pre_k_info) list)
    (clause : generated_clause_ir) : relational_generated_clause_ir list =
  let lower_all facts = List.filter_map (relationalize_clause_fact ~pre_k_map) facts in
  let hypotheses = lower_all clause.hypotheses in
  let conclusions = lower_all clause.conclusions in
  if conclusions = [] then []
  else
    expand_relational_hypotheses hypotheses
    |> List.filter_map (fun hypotheses ->
           match normalize_relational_hypotheses hypotheses with
           | None -> None
           | Some hypotheses -> Some { origin = clause.origin; anchor = clause.anchor; hypotheses; conclusions })
