open Ast
open Support
open Proof_kernel_types

let build_proof_step_contracts ~(product_steps : product_step_ir list)
    ~(pre_k_map : (Ast.hexpr * Temporal_support.pre_k_info) list)
    ~(initial_product_state : product_state_ir)
    ~(symbolic_generated_clauses : relational_generated_clause_ir list) :
    proof_step_contract_ir list =
  let slot_to_current_expr =
    let add acc (_h, info) =
      info.Support.names
      |> List.mapi (fun idx name ->
             let lowered =
               if idx = 0 then Ast.HNow info.Support.expr else Ast.HPreK (info.Support.expr, idx)
             in
             (name, lowered))
      |> List.rev_append acc
    in
    List.fold_left add [] pre_k_map
  in
  let current_expr_to_next_slot =
    let add acc (_h, info) =
      match info.Support.expr.iexpr with
      | IVar base_var -> (base_var, info.Support.names) :: acc
      | _ -> acc
    in
    List.fold_left add [] pre_k_map
  in
  let rec rewrite_iexpr_post (e : Ast.iexpr) : Ast.iexpr =
    let iexpr =
      match e.iexpr with
      | Ast.ILitInt _ | Ast.ILitBool _ | Ast.IVar _ -> e.iexpr
      | Ast.IPar inner -> Ast.IPar (rewrite_iexpr_post inner)
      | Ast.IUn (op, inner) -> Ast.IUn (op, rewrite_iexpr_post inner)
      | Ast.IBin (op, a, b) -> Ast.IBin (op, rewrite_iexpr_post a, rewrite_iexpr_post b)
    in
    { e with iexpr }
  in
  let rec rewrite_hexpr_post (h : Ast.hexpr) : Ast.hexpr =
    match h with
    | Ast.HNow ({ Ast.iexpr = Ast.IVar name; _ } as e) -> (
        match List.assoc_opt name slot_to_current_expr with
        | Some lowered -> lowered
        | None -> Ast.HNow (rewrite_iexpr_post e))
    | Ast.HNow e -> Ast.HNow (rewrite_iexpr_post e)
    | Ast.HPreK (e, k) -> Ast.HPreK (rewrite_iexpr_post e, k)
  in
  let rewrite_fo_post (f : Ast.fo) : Ast.fo =
    match f with
    | Ast.FRel (h1, r, h2) -> Ast.FRel (rewrite_hexpr_post h1, r, rewrite_hexpr_post h2)
    | Ast.FPred (id, hs) -> Ast.FPred (id, List.map rewrite_hexpr_post hs)
  in
  let rec rewrite_ltl_post (f : Ast.ltl) : Ast.ltl =
    match f with
    | Ast.LTrue | Ast.LFalse -> f
    | Ast.LAtom fo -> Ast.LAtom (rewrite_fo_post fo)
    | Ast.LNot a -> Ast.LNot (rewrite_ltl_post a)
    | Ast.LAnd (a, b) -> Ast.LAnd (rewrite_ltl_post a, rewrite_ltl_post b)
    | Ast.LOr (a, b) -> Ast.LOr (rewrite_ltl_post a, rewrite_ltl_post b)
    | Ast.LImp (a, b) -> Ast.LImp (rewrite_ltl_post a, rewrite_ltl_post b)
    | Ast.LX a -> Ast.LX (rewrite_ltl_post a)
    | Ast.LG a -> Ast.LG (rewrite_ltl_post a)
    | Ast.LW (a, b) -> Ast.LW (rewrite_ltl_post a, rewrite_ltl_post b)
  in
  let rec rewrite_iexpr_pre (e : Ast.iexpr) : Ast.iexpr =
    let iexpr =
      match e.iexpr with
      | Ast.ILitInt _ | Ast.ILitBool _ | Ast.IVar _ -> e.iexpr
      | Ast.IPar inner -> Ast.IPar (rewrite_iexpr_pre inner)
      | Ast.IUn (op, inner) -> Ast.IUn (op, rewrite_iexpr_pre inner)
      | Ast.IBin (op, a, b) -> Ast.IBin (op, rewrite_iexpr_pre a, rewrite_iexpr_pre b)
    in
    { e with iexpr }
  in
  let slot_name_for_depth base_var depth =
    match List.assoc_opt base_var current_expr_to_next_slot with
    | None -> None
    | Some names ->
        let idx = depth - 1 in
        if idx < 0 || idx >= List.length names then None else Some (List.nth names idx)
  in
  let rec rewrite_hexpr_pre (h : Ast.hexpr) : Ast.hexpr =
    match h with
    | Ast.HNow ({ Ast.iexpr = Ast.IVar name; _ }) -> (
        match slot_name_for_depth name 1 with
        | Some slot -> Ast.HNow { Ast.iexpr = Ast.IVar slot; loc = None }
        | None -> h)
    | Ast.HNow e -> Ast.HNow (rewrite_iexpr_pre e)
    | Ast.HPreK (({ Ast.iexpr = Ast.IVar name; _ } as e), k) -> (
        match slot_name_for_depth name (k + 1) with
        | Some slot -> Ast.HNow { Ast.iexpr = Ast.IVar slot; loc = None }
        | None -> Ast.HPreK (rewrite_iexpr_pre e, k))
    | Ast.HPreK (e, k) -> Ast.HPreK (rewrite_iexpr_pre e, k)
  in
  let rewrite_fo_pre (f : Ast.fo) : Ast.fo =
    match f with
    | Ast.FRel (h1, r, h2) -> Ast.FRel (rewrite_hexpr_pre h1, r, rewrite_hexpr_pre h2)
    | Ast.FPred (id, hs) -> Ast.FPred (id, List.map rewrite_hexpr_pre hs)
  in
  let rec rewrite_ltl_pre (f : Ast.ltl) : Ast.ltl =
    match f with
    | Ast.LTrue | Ast.LFalse -> f
    | Ast.LAtom fo -> Ast.LAtom (rewrite_fo_pre fo)
    | Ast.LNot a -> Ast.LNot (rewrite_ltl_pre a)
    | Ast.LAnd (a, b) -> Ast.LAnd (rewrite_ltl_pre a, rewrite_ltl_pre b)
    | Ast.LOr (a, b) -> Ast.LOr (rewrite_ltl_pre a, rewrite_ltl_pre b)
    | Ast.LImp (a, b) -> Ast.LImp (rewrite_ltl_pre a, rewrite_ltl_pre b)
    | Ast.LX a -> Ast.LX (rewrite_ltl_pre a)
    | Ast.LG a -> Ast.LG (rewrite_ltl_pre a)
    | Ast.LW (a, b) -> Ast.LW (rewrite_ltl_pre a, rewrite_ltl_pre b)
  in
  let relational_fact_to_plain_formula (fact : relational_clause_fact_ir) : Ast.ltl option =
    match fact.desc with
    | RelFactPhaseFormula fo | RelFactFormula fo -> Some fo
    | RelFactFalse -> Some LFalse
    | RelFactProgramState _ | RelFactGuaranteeState _ -> None
  in
  let clause_to_post_formula (clause : relational_generated_clause_ir) : Ast.ltl option =
    let hyps =
      clause.hypotheses
      |> List.filter_map (fun fact ->
             match fact.time with
             | StepTickContext | CurrentTick -> relational_fact_to_plain_formula fact
             | PreviousTick -> None)
    in
    let concs =
      clause.conclusions
      |> List.filter_map (fun fact ->
             match fact.time with
             | CurrentTick -> relational_fact_to_plain_formula fact
             | PreviousTick | StepTickContext -> None)
    in
    let conj = function
      | [] -> None
      | f :: fs -> Some (List.fold_left (fun acc x -> LAnd (acc, x)) f fs)
    in
    match (conj hyps, conj concs) with
    | None, None -> None
    | None, Some c -> Some c
    | Some h, None -> Some h
    | Some h, Some c -> Some (LImp (h, c))
  in
  let is_structural_step_fact (fact : relational_clause_fact_ir) =
    match fact.desc with
    | RelFactProgramState _ | RelFactGuaranteeState _ -> true
    | _ -> false
  in
  let strip_structural_step_facts (clause : relational_generated_clause_ir) :
      relational_generated_clause_ir =
    {
      clause with
      hypotheses = List.filter (fun fact -> not (is_structural_step_fact fact)) clause.hypotheses;
      conclusions = List.filter (fun fact -> not (is_structural_step_fact fact)) clause.conclusions;
    }
  in
  let raw_clauses_for_step (step : product_step_ir) =
    symbolic_generated_clauses
    |> List.filter (fun (clause : relational_generated_clause_ir) ->
           match (clause.origin, clause.anchor) with
           | OriginPhaseStepPreSummary, _ -> false
           | _, ClauseAnchorProductStep anchored_step -> anchored_step = step
           | _, ClauseAnchorProductState _ -> false)
    |> List.map strip_structural_step_facts
  in
  let shift_post_fact (fact : relational_clause_fact_ir) =
    let desc =
      match fact.desc with
      | RelFactPhaseFormula fo -> RelFactPhaseFormula (rewrite_ltl_post fo)
      | RelFactFormula fo -> RelFactFormula (rewrite_ltl_post fo)
      | _ -> fact.desc
    in
    { fact with desc }
  in
  let clauses_for_step (step : product_step_ir) =
    raw_clauses_for_step step
    |> List.map (fun clause ->
           match clause.origin with
           | OriginPropagationNodeInvariant ->
               {
                 clause with
                 hypotheses = List.map shift_post_fact clause.hypotheses;
                 conclusions = List.map shift_post_fact clause.conclusions;
               }
           | OriginPropagationAutomatonCoherence
           | OriginPhaseStepSummary
           | OriginSafety
           | OriginSourceProductSummary
           | OriginPhaseStepPreSummary
           | OriginInitNodeInvariant
           | OriginInitAutomatonCoherence ->
               clause)
  in
  let same_product_state a b =
    a.prog_state = b.prog_state
    && a.assume_state_index = b.assume_state_index
    && a.guarantee_state_index = b.guarantee_state_index
  in
  let post_formula_for_step (step : product_step_ir) =
    clauses_for_step step
    |> List.filter_map clause_to_post_formula
    |> function
    | [] -> LTrue
    | f :: fs -> List.fold_left (fun acc x -> LAnd (acc, x)) f fs |> Fo_simplifier.simplify_fo
  in
  let entry_clauses_for (step : product_step_ir) =
    let predecessor_posts =
      product_steps
      |> List.filter (fun pred -> same_product_state pred.dst step.src)
      |> List.map post_formula_for_step
    in
    let disjuncts =
      if same_product_state step.src initial_product_state then LTrue :: predecessor_posts
      else predecessor_posts
    in
    let entry_formula =
      match disjuncts with
      | [] -> LTrue
      | f :: fs -> List.fold_left (fun acc x -> LOr (acc, x)) f fs |> Fo_simplifier.simplify_fo
    in
    [
      {
        origin = OriginPhaseStepPreSummary;
        anchor = ClauseAnchorProductStep step;
        hypotheses = [];
        conclusions =
          [
            {
              time = CurrentTick;
              desc = RelFactFormula (Fo_simplifier.simplify_fo (rewrite_ltl_pre entry_formula));
            };
          ];
      };
    ]
  in
  let build_step_contract (step : product_step_ir) =
    let entry_clauses = entry_clauses_for step in
    let post_clauses = clauses_for_step step in
    { step; entry_clauses; clauses = post_clauses }
  in
  List.map build_step_contract product_steps
