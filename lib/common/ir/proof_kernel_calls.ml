open Ast
open Support

module Abs = Normalized_program
open Proof_kernel_types

let fo_of_iexpr (e : iexpr) : ltl = Fo_specs.iexpr_to_fo_with_atoms [] e

let current_fact (desc : clause_fact_desc_ir) : clause_fact_ir = { time = CurrentTick; desc }

let invariants_for_state ~(node : Abs.node) ~(time : clause_time_ir) (state_name : Ast.ident) :
    clause_fact_ir list =
  List.filter_map
    (fun inv ->
      if (inv.is_eq && inv.state = state_name) || ((not inv.is_eq) && inv.state <> state_name) then
        Some ({ time; desc = FactFormula inv.formula } : clause_fact_ir)
      else None)
    node.specification.spec_invariants_state_rel

let lower_call_fact ~(pre_k_map : (Ast.hexpr * Support.pre_k_info) list) ~lower_clause_fact
    (fact : call_fact_ir) : call_fact_ir option =
  Option.map (fun lowered -> { fact with fact = lowered }) (lower_clause_fact ~pre_k_map fact.fact)

let lower_callee_summary_case ~(pre_k_map : (Ast.hexpr * Support.pre_k_info) list)
    ~lower_clause_fact (case : callee_summary_case_ir) : callee_summary_case_ir =
  let lower facts = List.filter_map (lower_call_fact ~pre_k_map ~lower_clause_fact) facts in
  {
    case with
    entry_facts = lower case.entry_facts;
    transition_facts = lower case.transition_facts;
    exported_post_facts = lower case.exported_post_facts;
  }

let lower_callee_tick_abi ~(pre_k_map : (Ast.hexpr * Support.pre_k_info) list)
    ~lower_clause_fact (abi : callee_tick_abi_ir) : callee_tick_abi_ir =
  { abi with cases = List.map (lower_callee_summary_case ~pre_k_map ~lower_clause_fact) abi.cases }

let find_node (nodes : Abs.node list) (name : Ast.ident) : Abs.node option =
  List.find_opt (fun (nd : Abs.node) -> nd.semantics.sem_nname = name) nodes

let find_external_summary (summaries : exported_node_summary_ir list) (name : Ast.ident) :
    exported_node_summary_ir option =
  List.find_opt (fun summary -> summary.signature.node_name = name) summaries

type resolved_callee =
  | Local of Abs.node
  | External of exported_node_summary_ir

let resolve_callee ~(nodes : Abs.node list) ~(external_summaries : exported_node_summary_ir list)
    (name : Ast.ident) : resolved_callee option =
  match find_node nodes name with
  | Some node -> Some (Local node)
  | None -> Option.map (fun summary -> External summary) (find_external_summary external_summaries name)

let fold_lefti f acc xs =
  let rec loop i acc = function
    | [] -> acc
    | x :: tl -> loop (i + 1) (f acc i x) tl
  in
  loop 0 acc xs

let collect_call_sites_with_paths (ts : Abs.transition list) :
    (Ast.transition * string * Ast.ident * Ast.iexpr list * Ast.ident list) list =
  let rec collect_stmt acc (t_ast : Ast.transition) path (s : Ast.stmt) =
    match s.stmt with
    | SCall (inst, args, outs) ->
        (t_ast, path, inst, args, outs) :: acc
    | SIf (_c, tbr, fbr) ->
        let acc =
          fold_lefti
            (fun acc idx stmt -> collect_stmt acc t_ast (Printf.sprintf "%s.t%d" path idx) stmt)
            acc tbr
        in
        fold_lefti
          (fun acc idx stmt -> collect_stmt acc t_ast (Printf.sprintf "%s.f%d" path idx) stmt)
          acc fbr
    | SMatch (_e, branches, def) ->
        let acc =
          fold_lefti
            (fun acc bidx (_ctor, body) ->
              fold_lefti
                (fun acc sidx stmt ->
                  collect_stmt acc t_ast (Printf.sprintf "%s.m%d.%d" path bidx sidx) stmt)
                acc body)
            acc branches
        in
        fold_lefti
          (fun acc idx stmt -> collect_stmt acc t_ast (Printf.sprintf "%s.d%d" path idx) stmt)
          acc def
    | SAssign _ | SSkip -> acc
  in
  List.fold_left
    (fun acc (t : Abs.transition) ->
      let t_ast = Abs.to_ast_transition t in
      let seed =
        match t_ast.attrs.uid with
        | Some uid -> Printf.sprintf "uid%d" uid
        | None -> Printf.sprintf "%s_to_%s" t_ast.src t_ast.dst
      in
      let acc =
        fold_lefti
          (fun acc idx stmt -> collect_stmt acc t_ast (Printf.sprintf "%s.g%d" seed idx) stmt)
          acc t_ast.attrs.ghost
      in
      let acc =
        fold_lefti
          (fun acc idx stmt -> collect_stmt acc t_ast (Printf.sprintf "%s.b%d" seed idx) stmt)
          acc t_ast.body
      in
      fold_lefti
        (fun acc idx stmt -> collect_stmt acc t_ast (Printf.sprintf "%s.i%d" seed idx) stmt)
        acc t_ast.attrs.instrumentation)
    [] ts
  |> List.rev

let callee_tick_abi_of_node ~(node : Abs.node) : callee_tick_abi_ir =
  let callee_ast = Abs.to_ast_node node in
  let input_ports =
    List.map (fun name -> { port_name = name; role = CallInputPort }) (Ast_utils.input_names_of_node callee_ast)
  in
  let output_ports =
    List.map (fun name -> { port_name = name; role = CallOutputPort }) (Ast_utils.output_names_of_node callee_ast)
  in
  let state_ports =
    { port_name = "st"; role = CallStatePort }
    :: List.map
         (fun v -> { port_name = v.vname; role = CallStatePort })
         node.semantics.sem_locals
  in
  let exported_post_facts_for_transition (t : Abs.transition) =
    let state_facts = invariants_for_state ~node ~time:CurrentTick t.dst in
    let ensure_facts =
      List.map (fun (ltl_o : Ast.ltl_o) -> current_fact (FactFormula ltl_o.value)) t.ensures
    in
    (state_facts @ ensure_facts) |> List.sort_uniq Stdlib.compare
  in
  let cases =
    List.mapi
      (fun idx (t : Abs.transition) ->
        let guard =
          match t.guard with
          | None -> []
          | Some g -> [ { fact_kind = CallEntryFact; fact = current_fact (FactFormula (fo_of_iexpr g)) } ]
        in
        let requires =
          List.map
            (fun ltl_o -> { fact_kind = CallEntryFact; fact = current_fact (FactFormula ltl_o.value) })
            t.requires
        in
        let transition_facts =
          { fact_kind = CallTransitionFact; fact = current_fact (FactProgramState t.dst) }
          :: List.map
               (fun ltl_o ->
                 { fact_kind = CallTransitionFact; fact = current_fact (FactFormula ltl_o.value) })
               t.ensures
        in
        let exported_post_facts =
          List.map
            (fun fact -> { fact_kind = CallExportedPostFact; fact })
            (exported_post_facts_for_transition t)
        in
        {
          case_name = Printf.sprintf "%s_to_%s_%d" t.src t.dst idx;
          entry_facts =
            ({ fact_kind = CallEntryFact; fact = current_fact (FactProgramState t.src) } :: guard)
            @ requires;
          transition_facts;
          exported_post_facts;
        })
      node.trans
  in
  {
    callee_node_name = node.semantics.sem_nname;
    input_ports;
    output_ports;
    state_ports;
    cases;
  }

let build_call_binding_pairs kind locals remotes =
  List.map2 (fun local_name remote_name -> { binding_kind = kind; local_name; remote_name }) locals remotes

let build_proof_step_contracts ~(product_steps : product_step_ir list)
    ~(pre_k_map : (Ast.hexpr * Support.pre_k_info) list)
    ~(initial_product_state : product_state_ir)
    ~(symbolic_generated_clauses : relational_generated_clause_ir list) :
    proof_step_contract_ir list =
  let module String_set = Set.Make (String) in
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
  let key_of_formula (fo : Ast.ltl) = Support.string_of_ltl fo in
  let key_of_step_contract ~(entry_formula : Ast.ltl) ~(post_formula : Ast.ltl) (step : product_step_ir) =
    String.concat "|"
      [
        step.program_transition_id;
        step.src.prog_state;
        string_of_int step.src.assume_state_index;
        string_of_int step.src.guarantee_state_index;
        step.dst.prog_state;
        string_of_int step.dst.assume_state_index;
        string_of_int step.dst.guarantee_state_index;
        key_of_formula entry_formula;
        key_of_formula post_formula;
      ]
  in
  let add_step_contract (seen, acc) (step : product_step_ir) =
    let entry_clauses = entry_clauses_for step in
    let entry_formula =
      entry_clauses
      |> List.filter_map clause_to_post_formula
      |> function
      | [] -> LTrue
      | f :: fs -> List.fold_left (fun a b -> LAnd (a, b)) f fs |> Fo_simplifier.simplify_fo
    in
    let post_clauses = clauses_for_step step in
    let post_formula =
      post_clauses
      |> List.filter_map clause_to_post_formula
      |> function
      | [] -> LTrue
      | f :: fs -> List.fold_left (fun a b -> LAnd (a, b)) f fs |> Fo_simplifier.simplify_fo
    in
    match entry_formula with
    | LFalse -> (seen, acc)
    | _ ->
        let key = key_of_step_contract ~entry_formula ~post_formula step in
        if String_set.mem key seen then (seen, acc)
        else
          ( String_set.add key seen,
            { step; entry_clauses; clauses = post_clauses } :: acc )
  in
  product_steps |> List.fold_left add_step_contract (String_set.empty, []) |> snd |> List.rev

type temporal_origin = {
  base_var : Ast.ident;
  depth : int;
}

let first_temporal_slot_for_input (pre_k_map : (Ast.hexpr * Support.pre_k_info) list)
    (input_name : Ast.ident) : Ast.ident option =
  List.find_map
    (fun (_, info) ->
      match (info.expr.iexpr, info.names) with
      | IVar x, name :: _ when x = input_name -> Some name
      | _ -> None)
    pre_k_map

let rec simple_relational_eq_vars (fo : Ast.ltl) : (Ast.ident * Ast.ident) option =
  match fo with
  | LAtom (FRel (HNow { iexpr = IVar lhs; _ }, REq, HNow { iexpr = IVar rhs; _ })) -> Some (lhs, rhs)
  | LNot (LNot inner) -> simple_relational_eq_vars inner
  | LOr (LTrue, inner) | LOr (inner, LTrue) -> simple_relational_eq_vars inner
  | _ -> None

let infer_output_history_links ~(output_names : Ast.ident list)
    ~(pre_k_map : (Ast.hexpr * Support.pre_k_info) list)
    ~(symbolic_clauses : relational_generated_clause_ir list) :
    (Ast.ident * Ast.ident * Ast.ident option) list =
  let first_slot_to_input =
    pre_k_map
    |> List.filter_map (fun (_, info) ->
           match (info.expr.iexpr, info.names) with
           | IVar input_name, first_slot :: _ -> Some (first_slot, input_name)
           | _ -> None)
  in
  symbolic_clauses
  |> List.filter (fun clause -> clause.origin = OriginSourceProductSummary)
  |> List.concat_map (fun clause ->
         clause.conclusions
         |> List.filter_map (fun fact ->
                match fact.desc with
                | RelFactFormula fo -> begin
                    match simple_relational_eq_vars fo with
                    | Some (lhs, rhs) when List.mem lhs output_names -> begin
                        match List.assoc_opt rhs first_slot_to_input with
                        | Some input_name -> Some (lhs, input_name, Some rhs)
                        | None -> None
                      end
                    | Some (lhs, rhs) when List.mem rhs output_names -> begin
                        match List.assoc_opt lhs first_slot_to_input with
                        | Some input_name -> Some (rhs, input_name, Some lhs)
                        | None -> None
                      end
                    | _ -> None
                  end
                | _ -> None))
  |> List.sort_uniq Stdlib.compare

let temporal_slots_by_var (pre_k_map : (Ast.hexpr * Support.pre_k_info) list) :
    (Ast.ident * Ast.ident list) list =
  pre_k_map
  |> List.filter_map (fun (_, info) ->
         match info.expr.iexpr with
         | IVar input_name -> Some (input_name, info.names)
         | _ -> None)

let slot_name_for_origin ~(slots_by_var : (Ast.ident * Ast.ident list) list)
    (origin : temporal_origin) : Ast.ident option =
  match List.assoc_opt origin.base_var slots_by_var with
  | None -> None
  | Some names ->
      let slot_index = origin.depth - 1 in
      if slot_index < 0 || slot_index >= List.length names then None else Some (List.nth names slot_index)

let rec temporal_env_remove (env : (Ast.ident * temporal_origin) list) (name : Ast.ident) :
    (Ast.ident * temporal_origin) list =
  List.remove_assoc name env

let temporal_env_set (env : (Ast.ident * temporal_origin) list) (name : Ast.ident) (origin : temporal_origin) :
    (Ast.ident * temporal_origin) list =
  (name, origin) :: temporal_env_remove env name

let temporal_env_find (env : (Ast.ident * temporal_origin) list) (name : Ast.ident) : temporal_origin option =
  List.assoc_opt name env

let merge_temporal_envs (envs : (Ast.ident * temporal_origin) list list) : (Ast.ident * temporal_origin) list =
  let all_names =
    envs |> List.concat_map (List.map fst) |> List.sort_uniq String.compare
  in
  List.filter_map
    (fun name ->
      match envs with
      | [] -> None
      | env0 :: rest -> (
          match List.assoc_opt name env0 with
          | None -> None
          | Some origin ->
              if List.for_all (fun env -> List.assoc_opt name env = Some origin) rest then Some (name, origin)
              else None))
    all_names

let rec compose_delay_relations_in_stmts ~(nodes : Abs.node list)
    ~(external_summaries : exported_node_summary_ir list)
    ~(instance_map : (Ast.ident * Ast.ident) list)
    ~(slots_by_var : (Ast.ident * Ast.ident list) list)
    ~(node_signature_of_ast : Ast.node -> node_signature_ir)
    ~(build_pre_k_infos : Ast.node -> (Ast.hexpr * Support.pre_k_info) list)
    ~(extract_delay_spec : Ast.ltl list -> (Ast.ident * Ast.ident) option)
    ~(of_node_analysis :
       node_name:Ast.ident ->
       nodes:Abs.node list ->
       external_summaries:exported_node_summary_ir list ->
       node:Abs.node ->
       analysis:Product_build.analysis ->
       node_ir)
    (env : (Ast.ident * temporal_origin) list)
    (stmts : Ast.stmt list) :
    instance_relation_ir list * (Ast.ident * temporal_origin) list =
  let rec compose_stmt env (s : Ast.stmt) : instance_relation_ir list * (Ast.ident * temporal_origin) list =
    match s.stmt with
    | SAssign (lhs, rhs) -> (
        match rhs.iexpr with
        | IVar v -> (
            match temporal_env_find env v with
            | Some origin -> ([], temporal_env_set env lhs origin)
            | None -> ([], temporal_env_remove env lhs))
        | _ -> ([], temporal_env_remove env lhs))
    | SSkip -> ([], env)
    | SCall (inst_name, args, outs) -> (
        match List.assoc_opt inst_name instance_map with
        | None ->
            let env' = List.fold_left temporal_env_remove env outs in
            ([], env')
        | Some callee_node_name -> (
            match resolve_callee ~nodes ~external_summaries callee_node_name with
            | None ->
                let env' = List.fold_left temporal_env_remove env outs in
                ([], env')
            | Some callee ->
                let input_names, output_names, output_history_links =
                  output_history_links_of_resolved_callee ~nodes ~external_summaries
                    ~node_signature_of_ast ~build_pre_k_infos ~extract_delay_spec ~of_node_analysis callee
                in
                let arg_bindings = List.combine input_names args in
                let relations, env_after_outputs =
                  output_history_links
                  |> List.fold_left
                       (fun (rels, env_acc) (out_name, in_name, callee_pre_name) ->
                         match List.find_index (fun name -> name = out_name) output_names with
                         | None -> (rels, env_acc)
                         | Some out_idx ->
                             if out_idx >= List.length outs then (rels, env_acc)
                             else
                               let caller_output = List.nth outs out_idx in
                               let history_links =
                                 [
                                   InstanceDelayHistoryLink
                                     {
                                       instance_name = inst_name;
                                       callee_node_name;
                                       caller_output;
                                       callee_input = in_name;
                                       callee_pre_name;
                                     };
                                 ]
                               in
                               let rels = history_links @ rels in
                               let origin =
                                 match List.assoc_opt in_name arg_bindings with
                                 | Some { iexpr = IVar v; _ } -> temporal_env_find env v
                                 | _ -> None
                               in
                               let rels, env_acc =
                                 match origin with
                                 | Some origin -> (
                                     let delayed_origin = { origin with depth = origin.depth + 1 } in
                                     let env_acc = temporal_env_set env_acc caller_output delayed_origin in
                                     match slot_name_for_origin ~slots_by_var delayed_origin with
                                     | Some caller_pre_name ->
                                         ( InstanceDelayCallerPreLink { caller_output; caller_pre_name } :: rels,
                                           env_acc )
                                     | None -> (rels, env_acc))
                                 | None ->
                                     let env_acc = temporal_env_remove env_acc caller_output in
                                     (rels, env_acc)
                               in
                               (rels, env_acc))
                       ([], List.fold_left temporal_env_remove env outs)
                in
                (List.rev relations, env_after_outputs)))
    | SIf (_cond, then_branch, else_branch) ->
        let rels_then, env_then =
          compose_delay_relations_in_stmts ~nodes ~external_summaries ~instance_map ~slots_by_var
            ~node_signature_of_ast ~build_pre_k_infos ~extract_delay_spec ~of_node_analysis env
            then_branch
        in
        let rels_else, env_else =
          compose_delay_relations_in_stmts ~nodes ~external_summaries ~instance_map ~slots_by_var
            ~node_signature_of_ast ~build_pre_k_infos ~extract_delay_spec ~of_node_analysis env
            else_branch
        in
        (rels_then @ rels_else, merge_temporal_envs [ env_then; env_else ])
    | SMatch (_scrutinee, branches, default_branch) ->
        let branch_results =
          List.map
            (fun (_ctor, body) ->
              compose_delay_relations_in_stmts ~nodes ~external_summaries ~instance_map
                ~slots_by_var ~node_signature_of_ast ~build_pre_k_infos ~extract_delay_spec
                ~of_node_analysis env body)
            branches
        in
        let default_rels, default_env =
          compose_delay_relations_in_stmts ~nodes ~external_summaries ~instance_map ~slots_by_var
            ~node_signature_of_ast ~build_pre_k_infos ~extract_delay_spec ~of_node_analysis env
            default_branch
        in
        let all_rels = (branch_results |> List.concat_map fst) @ default_rels in
        let all_envs = (branch_results |> List.map snd) @ [ default_env ] in
        (all_rels, merge_temporal_envs all_envs)
  in
  List.fold_left
    (fun (rels_acc, env_acc) stmt ->
      let rels, env_next = compose_stmt env_acc stmt in
      (rels_acc @ rels, env_next))
    ([], env) stmts

and output_history_links_of_resolved_callee ~(nodes : Abs.node list)
    ~(external_summaries : exported_node_summary_ir list)
    ~(node_signature_of_ast : Ast.node -> node_signature_ir)
    ~(build_pre_k_infos : Ast.node -> (Ast.hexpr * Support.pre_k_info) list)
    ~(extract_delay_spec : Ast.ltl list -> (Ast.ident * Ast.ident) option)
    ~(of_node_analysis :
       node_name:Ast.ident ->
       nodes:Abs.node list ->
       external_summaries:exported_node_summary_ir list ->
       node:Abs.node ->
       analysis:Product_build.analysis ->
       node_ir)
    (callee : resolved_callee) :
    Ast.ident list * Ast.ident list * (Ast.ident * Ast.ident * Ast.ident option) list =
  match callee with
  | Local callee_node ->
      let callee_ast = Abs.to_ast_node callee_node in
      let callee_pre_k_map = build_pre_k_infos callee_ast in
      let explicit_delay_spec_links =
        match extract_delay_spec callee_ast.specification.spec_guarantees with
        | Some (output_name, input_name) ->
            let caller_pre_name = first_temporal_slot_for_input callee_pre_k_map input_name in
            [ (output_name, input_name, caller_pre_name) ]
        | None -> []
      in
      let analysis =
        Product_build.analyze_node ~build:(Automata_generation.build_for_node callee_ast)
          ~node:callee_node
      in
      let normalized_ir =
        of_node_analysis ~node_name:callee_ast.semantics.sem_nname ~nodes ~external_summaries
          ~node:callee_node ~analysis
      in
      ( Ast_utils.input_names_of_node callee_ast,
        Ast_utils.output_names_of_node callee_ast,
        (explicit_delay_spec_links
        @ infer_output_history_links ~output_names:(Ast_utils.output_names_of_node callee_ast)
            ~pre_k_map:callee_pre_k_map ~symbolic_clauses:normalized_ir.symbolic_generated_clauses)
        |> List.sort_uniq Stdlib.compare )
  | External summary ->
      let summary_output_names = List.map (fun v -> v.vname) summary.signature.outputs in
      let explicit_delay_spec_links =
        match extract_delay_spec summary.guarantees with
        | Some (output_name, input_name) ->
            let caller_pre_name = first_temporal_slot_for_input summary.pre_k_map input_name in
            [ (output_name, input_name, caller_pre_name) ]
        | None -> []
      in
      ( List.map (fun v -> v.vname) summary.signature.inputs,
        summary_output_names,
        (explicit_delay_spec_links
        @ infer_output_history_links ~output_names:summary_output_names
            ~pre_k_map:summary.pre_k_map
            ~symbolic_clauses:summary.normalized_ir.symbolic_generated_clauses)
        |> List.sort_uniq Stdlib.compare )

let build_call_site_instantiations ~(nodes : Abs.node list)
    ~(external_summaries : exported_node_summary_ir list) ~(node : Abs.node)
    ~(node_signature_of_ast : Ast.node -> node_signature_ir)
    ~(build_pre_k_infos : Ast.node -> (Ast.hexpr * Support.pre_k_info) list)
    ~(extract_delay_spec : Ast.ltl list -> (Ast.ident * Ast.ident) option)
    ~(of_node_analysis :
       node_name:Ast.ident ->
       nodes:Abs.node list ->
       external_summaries:exported_node_summary_ir list ->
       node:Abs.node ->
       analysis:Product_build.analysis ->
       node_ir) : call_site_instantiation_ir list =
  let call_sites = collect_call_sites_with_paths node.trans in
  List.filter_map
    (fun ((t_ast : Ast.transition), path, inst_name, args, outs) ->
      match List.assoc_opt inst_name node.semantics.sem_instances with
      | None -> None
      | Some callee_node_name -> (
          match resolve_callee ~nodes ~external_summaries callee_node_name with
          | None -> None
          | Some callee ->
              let signature =
                match callee with
                | Local callee_node -> node_signature_of_ast (Abs.to_ast_node callee_node)
                | External summary -> summary.signature
              in
              let input_names = List.map (fun v -> v.vname) signature.inputs in
              let output_names = List.map (fun v -> v.vname) signature.outputs in
              let state_names = "st" :: List.map (fun v -> v.vname) signature.locals in
              let input_bindings =
                build_call_binding_pairs BindActualInput (List.map string_of_iexpr args) input_names
              in
              let output_bindings = build_call_binding_pairs BindActualOutput outs output_names in
              let pre_state_bindings =
                build_call_binding_pairs BindInstancePreState
                  (List.map (fun name -> Printf.sprintf "%s__pre_%s" inst_name name) state_names)
                  state_names
              in
              let post_state_bindings =
                build_call_binding_pairs BindInstancePostState
                  (List.map (fun name -> Printf.sprintf "%s__post_%s" inst_name name) state_names)
                  state_names
              in
              let call_site_id =
                match t_ast.attrs.uid with
                | Some uid -> Printf.sprintf "%s.call.%s" (string_of_int uid) path
                | None -> Printf.sprintf "%s.%s_to_%s.call.%s" node.semantics.sem_nname t_ast.src t_ast.dst path
              in
              let _ = build_pre_k_infos, extract_delay_spec, of_node_analysis in
              Some
                {
                  instance_name = inst_name;
                  call_site_id;
                  callee_node_name;
                  bindings = input_bindings @ output_bindings @ pre_state_bindings @ post_state_bindings;
                }))
    call_sites

let build_instance_relations ~(nodes : Abs.node list)
    ~(external_summaries : exported_node_summary_ir list) ~(node : Abs.node)
    ~(node_signature_of_ast : Ast.node -> node_signature_ir)
    ~(build_pre_k_infos : Ast.node -> (Ast.hexpr * Support.pre_k_info) list)
    ~(extract_delay_spec : Ast.ltl list -> (Ast.ident * Ast.ident) option)
    ~(of_node_analysis :
       node_name:Ast.ident ->
       nodes:Abs.node list ->
       external_summaries:exported_node_summary_ir list ->
       node:Abs.node ->
       analysis:Product_build.analysis ->
       node_ir) : instance_relation_ir list =
  let n_ast = Abs.to_ast_node node in
  let pre_k_map = build_pre_k_infos n_ast in
  let slots_by_var = temporal_slots_by_var pre_k_map in
  let invariant_relations =
    List.concat_map
      (fun (inst_name, node_name) ->
        match resolve_callee ~nodes ~external_summaries node_name with
        | None -> []
        | Some callee ->
            let user_invariants, state_invariants =
              match callee with
              | Local inst_node ->
                  (inst_node.attrs.invariants_user, inst_node.specification.spec_invariants_state_rel)
              | External summary -> (summary.user_invariants, summary.state_invariants)
            in
            let user =
              List.map
                (fun inv ->
                  InstanceUserInvariant
                    {
                      instance_name = inst_name;
                      callee_node_name = node_name;
                      invariant_id = inv.inv_id;
                      invariant_expr = inv.inv_expr;
                    })
                user_invariants
            in
            let state_rel =
              List.map
                (fun inv ->
                  InstanceStateInvariant
                    {
                      instance_name = inst_name;
                      callee_node_name = node_name;
                      state_name = inv.state;
                      is_eq = inv.is_eq;
                      formula = inv.formula;
                    })
                state_invariants
            in
            user @ state_rel)
      node.semantics.sem_instances
  in
  let delay_relations =
    let initial_temporal_env =
      slots_by_var
      |> List.map (fun (base_var, _slots) -> (base_var, { base_var; depth = 0 }))
    in
    node.trans
    |> List.concat_map (fun (t : Abs.transition) ->
           fst
             (compose_delay_relations_in_stmts ~nodes ~external_summaries
                ~instance_map:node.semantics.sem_instances ~slots_by_var ~node_signature_of_ast
                ~build_pre_k_infos ~extract_delay_spec ~of_node_analysis initial_temporal_env
                t.body))
    |> List.sort_uniq Stdlib.compare
  in
  invariant_relations @ delay_relations
