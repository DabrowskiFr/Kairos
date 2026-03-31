open Ast
open Generated_names
open Temporal_support
open Ast_pretty
open Proof_kernel_types
module Abs = Ir

let simplify_fo (f : Fo_formula.t) : Fo_formula.t =
  match Fo_z3_solver.simplify_fo_formula f with Some simplified -> simplified | None -> f

let same_product_state (a : Abs.product_state) (b : product_state_ir) : bool =
  String.equal a.prog_state b.prog_state
  && a.assume_state_index = b.assume_state_index
  && a.guarantee_state_index = b.guarantee_state_index

let same_product_state_ir (a : product_state_ir) (b : product_state_ir) : bool =
  String.equal a.prog_state b.prog_state
  && a.assume_state_index = b.assume_state_index
  && a.guarantee_state_index = b.guarantee_state_index

let same_automaton_edge_ir (a : automaton_edge_ir) (b : automaton_edge_ir) : bool =
  a.src_index = b.src_index
  && a.dst_index = b.dst_index
  && simplify_fo a.guard = simplify_fo b.guard

let same_product_case_step (case : Abs.product_case) (step : product_step_ir) : bool =
  case.step_class
  =
  (match step.step_kind with
  | StepSafe -> Abs.Safe
  | StepBadAssumption -> Abs.Bad_assumption
  | StepBadGuarantee -> Abs.Bad_guarantee)
  && same_product_state case.product_dst step.dst
  && simplify_fo case.guarantee_guard = simplify_fo step.guarantee_edge.guard

let build_proof_step_contracts ~(node : Abs.node) ~(reactive_program : reactive_program_ir)
    ~(product_steps : product_step_ir list)
    ~(pre_k_map : (Ast.hexpr * Temporal_support.pre_k_info) list)
    ~(initial_product_state : product_state_ir)
    ~(symbolic_generated_clauses : relational_generated_clause_ir list) :
    proof_step_contract_ir list =
  let transition_index_by_id =
    reactive_program.transitions
    |> List.mapi (fun idx (tr : reactive_transition_ir) -> (tr.transition_id, idx))
    |> List.to_seq |> Hashtbl.of_seq
  in
  let product_contract_of_step (step : product_step_ir) : Abs.product_contract option =
    match Hashtbl.find_opt transition_index_by_id step.program_transition_id with
    | None -> None
    | Some program_transition_index ->
        List.find_opt
          (fun (pc : Abs.product_contract) ->
            pc.program_transition_index = program_transition_index
            && same_product_state pc.product_src step.src
            && simplify_fo pc.assume_guard = simplify_fo step.assume_edge.guard)
          node.product_transitions
  in
  let slot_to_current_expr =
    let add acc (_h, info) =
      info.Temporal_support.names
      |> List.mapi (fun idx name ->
             let lowered =
               if idx = 0 then Ast.HNow info.Temporal_support.expr else Ast.HPreK (info.Temporal_support.expr, idx)
             in
             (name, lowered))
      |> List.rev_append acc
    in
    List.fold_left add [] pre_k_map
  in
  let current_expr_to_next_slot =
    let add acc (_h, info) =
      match info.Temporal_support.expr.iexpr with
      | IVar base_var -> (base_var, info.Temporal_support.names) :: acc
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
  let rewrite_fo_post (f : Ast.fo_atom) : Ast.fo_atom =
    match f with
    | Ast.FRel (h1, r, h2) -> Ast.FRel (rewrite_hexpr_post h1, r, rewrite_hexpr_post h2)
    | Ast.FPred (id, hs) -> Ast.FPred (id, List.map rewrite_hexpr_post hs)
  in
  let rec rewrite_ltl_post (f : Ast.ltl) : Ast.ltl =
    match f with
    | Ast.LTrue | Ast.LFalse -> f
    | Ast.LAtom fo_atom -> Ast.LAtom (rewrite_fo_post fo_atom)
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
  let rewrite_fo_pre (f : Ast.fo_atom) : Ast.fo_atom =
    match f with
    | Ast.FRel (h1, r, h2) -> Ast.FRel (rewrite_hexpr_pre h1, r, rewrite_hexpr_pre h2)
    | Ast.FPred (id, hs) -> Ast.FPred (id, List.map rewrite_hexpr_pre hs)
  in
  let rec rewrite_ltl_pre (f : Ast.ltl) : Ast.ltl =
    match f with
    | Ast.LTrue | Ast.LFalse -> f
    | Ast.LAtom fo_atom -> Ast.LAtom (rewrite_fo_pre fo_atom)
    | Ast.LNot a -> Ast.LNot (rewrite_ltl_pre a)
    | Ast.LAnd (a, b) -> Ast.LAnd (rewrite_ltl_pre a, rewrite_ltl_pre b)
    | Ast.LOr (a, b) -> Ast.LOr (rewrite_ltl_pre a, rewrite_ltl_pre b)
    | Ast.LImp (a, b) -> Ast.LImp (rewrite_ltl_pre a, rewrite_ltl_pre b)
    | Ast.LX a -> Ast.LX (rewrite_ltl_pre a)
    | Ast.LG a -> Ast.LG (rewrite_ltl_pre a)
    | Ast.LW (a, b) -> Ast.LW (rewrite_ltl_pre a, rewrite_ltl_pre b)
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
      | RelFactPhaseFormula fo_atom -> RelFactPhaseFormula (rewrite_ltl_post fo_atom)
      | RelFactFormula fo_atom -> RelFactFormula (rewrite_ltl_post fo_atom)
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
  let entry_clauses_for_steps (steps : product_step_ir list) =
    match steps with
    | [] -> []
    | step :: _ -> (
        match product_contract_of_step step with
        | None -> []
        | Some pc ->
        pc.requires
        |> List.map (fun (f : Ir.contract_formula) ->
               {
                 origin = OriginPhaseStepPreSummary;
                 anchor = ClauseAnchorProductStep step;
                 hypotheses = [];
                 conclusions =
                   [
                     {
                       time = CurrentTick;
                       desc = RelFactFormula (Fo_simplifier.simplify_ltl (rewrite_ltl_pre f.value));
                     };
                   ];
               })
      )
  in
  let dedup_clauses (clauses : relational_generated_clause_ir list) =
    List.sort_uniq Stdlib.compare clauses
  in
  let safe_group_key (step : product_step_ir) =
    (step.program_transition_id, step.src, step.assume_edge)
  in
  let safe_groups = Hashtbl.create 16 in
  let safe_order = ref [] in
  let singleton_contract step =
    let steps = [ step ] in
    let entry_clauses = entry_clauses_for_steps steps in
    let clauses = clauses_for_step step in
    { steps; entry_clauses; clauses }
  in
  let contracts_rev = ref [] in
  List.iter
    (fun (step : product_step_ir) ->
      match step.step_kind with
      | StepSafe ->
          let key = safe_group_key step in
          if not (Hashtbl.mem safe_groups key) then safe_order := key :: !safe_order;
          let prev = Hashtbl.find_opt safe_groups key |> Option.value ~default:[] in
          Hashtbl.replace safe_groups key (step :: prev)
      | StepBadAssumption | StepBadGuarantee -> contracts_rev := singleton_contract step :: !contracts_rev)
    product_steps;
  let safe_contracts =
    List.rev !safe_order
    |> List.map (fun key ->
           let steps = Hashtbl.find safe_groups key |> List.rev in
           let entry_clauses = entry_clauses_for_steps steps in
           let clauses = steps |> List.concat_map clauses_for_step |> dedup_clauses in
           { steps; entry_clauses; clauses })
  in
  safe_contracts @ List.rev !contracts_rev
