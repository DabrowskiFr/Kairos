open Ast
open Generated_names
open Temporal_support
open Ast_pretty
open Fo_specs
open Collect
open Fo_formula

module Abs = Ir
module PT = Product_types
open Proof_kernel_types

let simplify_fo (f : Fo_formula.t) : Fo_formula.t =
  match Fo_z3_solver.simplify_fo_formula f with Some simplified -> simplified | None -> f

let same_product_state_ref (a : Abs.product_state) (b : product_state_ir) =
  String.equal a.prog_state b.prog_state
  && a.assume_state_index = b.assume_state_index
  && a.guarantee_state_index = b.guarantee_state_index

let same_safe_case_step (case : Abs.safe_product_case) (step : product_step_ir) =
  step.step_kind = StepSafe
  && same_product_state_ref case.product_dst step.dst
  && simplify_fo case.guarantee_guard = simplify_fo step.guarantee_edge.guard

let same_unsafe_case_step (case : Abs.unsafe_product_case) (step : product_step_ir) =
  step.step_kind = StepBadGuarantee
  && same_product_state_ref case.product_dst step.dst
  && simplify_fo case.guarantee_guard = simplify_fo step.guarantee_edge.guard

let product_transition_index_of_step (step : product_step_ir) : int option =
  let raw =
    match String.starts_with ~prefix:"tr_" step.program_transition_id with
    | true -> String.sub step.program_transition_id 3 (String.length step.program_transition_id - 3)
    | false -> ""
  in
  let len = String.length raw in
  let rec first_non_digit i =
    if i >= len then len
    else
      match raw.[i] with
      | '0' .. '9' -> first_non_digit (i + 1)
      | _ -> i
  in
  let prefix_len = first_non_digit 0 in
  if prefix_len = 0 then None else int_of_string_opt (String.sub raw 0 prefix_len)

let product_contract_of_step ~(node : Abs.node) (step : product_step_ir) :
    Abs.product_contract option =
  match product_transition_index_of_step step with
  | None -> None
  | Some idx ->
      List.find_opt
        (fun (pc : Abs.product_contract) ->
          pc.identity.program_transition_index = idx
          && same_product_state_ref pc.identity.product_src step.src
          && simplify_fo pc.identity.assume_guard = simplify_fo step.assume_edge.guard
          &&
          match step.step_kind with
          | StepSafe -> List.exists (fun case -> same_safe_case_step case step) pc.safe_cases
          | StepBadGuarantee ->
              List.exists (fun case -> same_unsafe_case_step case step) pc.unsafe_cases
          | StepBadAssumption -> false)
        node.product_transitions

let build_source_summary_clauses ~(node : Abs.node) ~(analysis : Product_build.analysis)
    ~(steps : product_step_ir list) ~automaton_guard_fo : generated_clause_ir list =
  let _analysis = analysis in
  let current (desc : clause_fact_desc_ir) : clause_fact_ir = { time = CurrentTick; desc } in
  let product_contracts_of_step (step : product_step_ir) : Abs.product_contract list =
    match product_contract_of_step ~node step with
    | None -> []
    | Some pc -> [ pc ]
  in
  let guarantee_propagation_requires (pc : Abs.product_contract) : Fo_formula.t list =
    pc.common.requires
    |> List.filter_map (fun (f : Abs.contract_formula) ->
           match f.meta.origin with
           | Some Formula_origin.GuaranteePropagation -> Some f.logic
           | _ -> None)
  in
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
  let rec fo_mentions_current_input (f : Fo_formula.t) =
    match f with
    | Fo_formula.FTrue | Fo_formula.FFalse -> false
    | Fo_formula.FAtom (FRel (a, _, b)) -> hexpr_mentions_current_input a || hexpr_mentions_current_input b
    | Fo_formula.FAtom (FPred (_, hs)) -> List.exists hexpr_mentions_current_input hs
    | Fo_formula.FNot inner -> fo_mentions_current_input inner
    | Fo_formula.FAnd (a, b) | Fo_formula.FOr (a, b) | Fo_formula.FImp (a, b) ->
        fo_mentions_current_input a || fo_mentions_current_input b
  in
  let rec normalize_source_summary (f : Fo_formula.t) : Fo_formula.t =
    match f with
    | Fo_formula.FNot (Fo_formula.FOr (Fo_formula.FNot a, Fo_formula.FNot b)) ->
        Fo_formula.FAnd (normalize_source_summary a, normalize_source_summary b)
    | Fo_formula.FNot inner -> begin
        match normalize_source_summary inner with
        | Fo_formula.FTrue -> Fo_formula.FFalse
        | Fo_formula.FFalse -> Fo_formula.FTrue
        | inner -> Fo_formula.FNot inner
      end
    | Fo_formula.FAnd (a, b) -> begin
        match (normalize_source_summary a, normalize_source_summary b) with
        | Fo_formula.FFalse, _ | _, Fo_formula.FFalse -> Fo_formula.FFalse
        | Fo_formula.FTrue, rhs -> rhs
        | lhs, Fo_formula.FTrue -> lhs
        | lhs, rhs -> Fo_formula.FAnd (lhs, rhs)
      end
    | Fo_formula.FOr (a, b) -> begin
        match (normalize_source_summary a, normalize_source_summary b) with
        | Fo_formula.FTrue, _ | _, Fo_formula.FTrue -> Fo_formula.FTrue
        | Fo_formula.FFalse, rhs -> rhs
        | lhs, Fo_formula.FFalse -> lhs
        | lhs, rhs -> Fo_formula.FOr (lhs, rhs)
      end
    | Fo_formula.FImp (a, b) ->
        Fo_formula.FImp (normalize_source_summary a, normalize_source_summary b)
    | Fo_formula.FTrue | Fo_formula.FFalse | Fo_formula.FAtom _ -> f
  in
  let term_or a b = normalize_source_summary (Fo_formula.FOr (a, b)) in
  let term_and a b = normalize_source_summary (Fo_formula.FAnd (a, b)) in
  let term_not a = normalize_source_summary (Fo_formula.FNot a) in
  let rec phase_summary_obviously_inconsistent (f : Fo_formula.t) : bool =
    match normalize_source_summary f with
    | Fo_formula.FFalse -> true
    | Fo_formula.FAtom (FRel (HNow { iexpr = IVar x; _ }, RNeq, HNow { iexpr = IVar y; _ }))
      when String.equal x y ->
        true
    | Fo_formula.FNot (Fo_formula.FAtom (FRel (HNow { iexpr = IVar x; _ }, REq, HNow { iexpr = IVar y; _ })))
      when String.equal x y ->
        true
    | Fo_formula.FNot Fo_formula.FTrue -> true
    | Fo_formula.FAnd (a, b) ->
        phase_summary_obviously_inconsistent a || phase_summary_obviously_inconsistent b
    | _ -> false
  in
  let same_product_state (a : product_state_ir) (b : product_state_ir) =
    a.prog_state = b.prog_state
    && a.assume_state_index = b.assume_state_index
    && a.guarantee_state_index = b.guarantee_state_index
  in
  let all_states =
    steps
    |> List.concat_map (fun (step : product_step_ir) -> [ step.src; step.dst ])
    |> List.sort_uniq Stdlib.compare
  in
  let source_summaries =
    all_states
    |> List.filter_map (fun (st : product_state_ir) ->
           let formulas =
             steps
             |> List.filter (fun (step : product_step_ir) ->
                    same_product_state step.src st && step.step_kind = StepSafe)
             |> List.concat_map product_contracts_of_step
             |> List.concat_map guarantee_propagation_requires
             |> List.filter (fun fo_atom -> not (fo_mentions_current_input fo_atom))
             |> List.sort_uniq Stdlib.compare
           in
           let phase_formula =
             match formulas with
             | [] -> None
             | f :: rest ->
                 Some
                   (List.fold_left
                      (fun acc fo_atom -> Fo_formula.FOr (acc, fo_atom))
                      f rest
                   |> normalize_source_summary)
           in
           match phase_formula with
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
  let raw_summaries = source_summaries in
  let phase_formula_of_clause (clause : generated_clause_ir) =
    clause.conclusions
    |> List.find_map (fun (fact : clause_fact_ir) ->
           match (fact.time, fact.desc) with
           | CurrentTick, FactPhaseFormula fo_formula -> Some fo_formula
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
      | Some st, Some fo_atom ->
          let key = (st.prog_state, st.guarantee_state_index) in
          let merged =
            match Hashtbl.find_opt raw_formula_table key with
            | None -> fo_atom
            | Some prev -> term_or prev fo_atom
          in
          Hashtbl.replace raw_formula_table key merged
      | _ -> ())
    raw_summaries;
  let by_prog_state = Hashtbl.create 16 in
  Hashtbl.iter
    (fun ((prog_state, gidx) as key) fo_atom ->
      let prev = Hashtbl.find_opt by_prog_state prog_state |> Option.value ~default:[] in
      Hashtbl.replace by_prog_state prog_state ((gidx, fo_atom, key) :: prev))
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
  let guarantee_propagation_requires (pc : Abs.product_contract) : Fo_formula.t list =
    pc.common.requires
    |> List.filter_map (fun (f : Abs.contract_formula) ->
           match f.meta.origin with
           | Some Formula_origin.GuaranteePropagation -> Some f.logic
           | _ -> None)
  in
  let rec split_top_level_or (f : Fo_formula.t) : Fo_formula.t list =
    match f with
    | Fo_formula.FOr (a, b) -> split_top_level_or a @ split_top_level_or b
    | _ -> [ f ]
  in
  let rec normalize_phase_summary (f : Fo_formula.t) : Fo_formula.t =
    match f with
    | Fo_formula.FNot (Fo_formula.FOr (Fo_formula.FNot a, Fo_formula.FNot b)) ->
        Fo_formula.FAnd (normalize_phase_summary a, normalize_phase_summary b)
    | Fo_formula.FNot inner -> Fo_formula.FNot (normalize_phase_summary inner)
    | Fo_formula.FAnd (a, b) ->
        Fo_formula.FAnd (normalize_phase_summary a, normalize_phase_summary b)
    | Fo_formula.FOr (a, b) ->
        Fo_formula.FOr (normalize_phase_summary a, normalize_phase_summary b)
    | Fo_formula.FImp (a, b) ->
        Fo_formula.FImp (normalize_phase_summary a, normalize_phase_summary b)
    | Fo_formula.FTrue | Fo_formula.FFalse | Fo_formula.FAtom _ -> f
  in
  let compatibility_phase_formula_for_step (step : product_step_ir) =
    match product_contract_of_step ~node step with
    | None -> None
    | Some pc ->
        guarantee_propagation_requires pc
        |> List.sort_uniq Stdlib.compare
        |> function
        | [] -> None
        | f :: rest ->
            Some
              (List.fold_left (fun acc fo_atom -> Fo_formula.FOr (acc, fo_atom)) f rest
              |> normalize_phase_summary)
  in
  let invariants_for_state state_name =
    node.source_info.state_invariants
    |> List.filter_map (fun (inv : Ast.invariant_state_rel) ->
           if inv.state = state_name then
             Some (current (FactFormula (Fo_specs.fo_formula_of_non_temporal_ltl_exn inv.formula)))
           else None)
  in
  let init_goal_facts =
    node.coherency_goals
    |> List.map (fun (f : Abs.contract_formula) -> current (FactFormula f.logic))
  in
  let init_clauses =
    [
      ({
        origin = OriginInitNodeInvariant;
        anchor = ClauseAnchorProductState initial_state;
        hypotheses = [ current (FactProgramState initial_state.prog_state) ];
        conclusions = current (FactProgramState initial_state.prog_state) :: init_goal_facts;
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
              match compatibility_phase_formula_for_step step with
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

let lower_clause_fact ~(pre_k_map : (Ast.hexpr * Temporal_support.pre_k_info) list) (fact : clause_fact_ir) :
    clause_fact_ir option =
  let temporal_bindings = temporal_bindings_of_pre_k_map ~pre_k_map in
  let lower_desc = function
    | FactProgramState _ as desc -> Some desc
    | FactGuaranteeState _ as desc -> Some desc
    | FactPhaseFormula fo_formula ->
        Option.map (fun fo_formula' -> FactPhaseFormula fo_formula')
          (lower_fo_formula_temporal_bindings ~temporal_bindings fo_formula)
    | FactFalse -> Some FactFalse
    | FactFormula fo_formula ->
        Option.map (fun fo_formula' -> FactFormula fo_formula')
          (lower_fo_formula_temporal_bindings ~temporal_bindings fo_formula)
  in
  Option.map (fun desc -> { fact with desc }) (lower_desc fact.desc)

let lower_generated_clause ~(pre_k_map : (Ast.hexpr * Temporal_support.pre_k_info) list)
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
      if
        List.exists
          (fun (fact : clause_fact_ir) ->
            fact.desc = FactFormula Fo_formula.FFalse || fact.desc = FactFalse)
          hypotheses
      then None
      else Some { clause with hypotheses; conclusions }
  | _ -> None

let relationalize_clause_fact ~(pre_k_map : (Ast.hexpr * Temporal_support.pre_k_info) list)
    (fact : clause_fact_ir) : relational_clause_fact_ir option =
  let temporal_bindings = temporal_bindings_of_pre_k_map ~pre_k_map in
  let rel_desc = function
    | FactProgramState st -> Some (RelFactProgramState st)
    | FactGuaranteeState idx -> Some (RelFactGuaranteeState idx)
    | FactPhaseFormula fo_formula ->
        Option.map (fun fo_formula' -> RelFactPhaseFormula fo_formula')
          (lower_fo_formula_temporal_bindings ~temporal_bindings fo_formula)
    | FactFormula fo_formula ->
        Option.map (fun fo_formula' -> RelFactFormula fo_formula')
          (lower_fo_formula_temporal_bindings ~temporal_bindings fo_formula)
    | FactFalse -> Some RelFactFalse
  in
  Option.map (fun desc -> { time = fact.time; desc }) (rel_desc fact.desc)

let expand_relational_hypotheses (facts : relational_clause_fact_ir list) :
    relational_clause_fact_ir list list =
  let rec expand_one acc = function
    | [] -> [ List.rev acc ]
    | ({ desc = RelFactFormula (Fo_formula.FOr (a, b)); _ } as fact) :: tl ->
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
    | RelFactFormula a, RelFactFormula b ->
        Some (RelFactFormula (Fo_simplifier.simplify_fo (Fo_formula.FAnd (a, b))))
    | _ -> None
  in
  let rec insert acc fact =
    match acc with
    | [] -> Some [ fact ]
    | hd :: tl ->
        if hd.time = fact.time then
          match combine_formula hd.desc fact.desc with
          | Some (RelFactFormula Fo_formula.FFalse) -> None
          | Some desc -> Some ({ hd with desc } :: tl)
          | None -> Option.map (fun tl' -> hd :: tl') (insert tl fact)
        else
          Option.map (fun tl' -> hd :: tl') (insert tl fact)
  in
  let rec fold acc = function
    | [] ->
        Some
          (List.filter
             (fun (fact : relational_clause_fact_ir) ->
               fact.desc <> RelFactFormula Fo_formula.FTrue)
             acc)
    | ({ desc = RelFactFormula Fo_formula.FFalse; _ } : relational_clause_fact_ir) :: _ -> None
    | ({ desc = RelFactFalse; _ } : relational_clause_fact_ir) :: _ -> None
    | fact :: tl -> (
        match insert acc fact with
        | None -> None
        | Some acc' -> fold acc' tl)
  in
  fold [] facts

let relationalize_generated_clause ~(pre_k_map : (Ast.hexpr * Temporal_support.pre_k_info) list)
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
