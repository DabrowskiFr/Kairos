open Ast
open Support
open Fo_specs
open Collect

module Abs = Abstract_model
module PT = Product_types

type automaton_role =
  | Assume
  | Guarantee
[@@deriving yojson]

type reactive_transition_ir = {
  src_state : Ast.ident;
  dst_state : Ast.ident;
  guard : Ast.ltl;
  (* Execution-level transition body — needed to generate Why3 without OBC+. *)
  guard_iexpr : Ast.iexpr option;
  requires : Ast.ltl_o list;
  ensures : Ast.ltl_o list;
  ghost_stmts : Ast.stmt list;
  body_stmts : Ast.stmt list;
  instrumentation_stmts : Ast.stmt list;
}
[@@deriving yojson]

type reactive_program_ir = {
  node_name : Ast.ident;
  init_state : Ast.ident;
  states : Ast.ident list;
  transitions : reactive_transition_ir list;
}
[@@deriving yojson]

type automaton_edge_ir = {
  src_index : int;
  dst_index : int;
  guard : Ast.ltl;
}
[@@deriving yojson]

type safety_automaton_ir = {
  role : automaton_role;
  initial_state_index : int;
  bad_state_index : int option;
  state_labels : (int * string) list;
  edges : automaton_edge_ir list;
}
[@@deriving yojson]

type product_state_ir = {
  prog_state : Ast.ident;
  assume_state_index : int;
  guarantee_state_index : int;
}
[@@deriving yojson]

type product_step_kind =
  | StepSafe
  | StepBadAssumption
  | StepBadGuarantee
[@@deriving yojson]

type product_step_origin =
  | StepFromExplicitExploration
  | StepFromFallbackSynthesis
[@@deriving yojson]

type product_step_ir = {
  src : product_state_ir;
  dst : product_state_ir;
  program_transition : Ast.ident * Ast.ident;
  program_guard : Ast.ltl;
  assume_edge : automaton_edge_ir;
  guarantee_edge : automaton_edge_ir;
  step_kind : product_step_kind;
  step_origin : product_step_origin;
}
[@@deriving yojson]

type product_coverage_ir =
  | CoverageEmpty
  | CoverageExplicit
  | CoverageFallback
[@@deriving yojson]

type generated_clause_origin =
  | OriginSourceProductSummary
  | OriginPhaseStepPreSummary
  | OriginPhaseStepSummary
  | OriginSafety
  | OriginInitNodeInvariant
  | OriginInitAutomatonCoherence
  | OriginPropagationNodeInvariant
  | OriginPropagationAutomatonCoherence
[@@deriving yojson]

type clause_time_ir =
  | CurrentTick
  | PreviousTick
  | StepTickContext
[@@deriving yojson]

type clause_fact_desc_ir =
  | FactProgramState of Ast.ident
  | FactGuaranteeState of int
  | FactPhaseFormula of Ast.ltl
  | FactFormula of Ast.ltl
  | FactFalse
[@@deriving yojson]

type clause_fact_ir = {
  time : clause_time_ir;
  desc : clause_fact_desc_ir;
}
[@@deriving yojson]

type generated_clause_anchor_ir =
  | ClauseAnchorProductState of product_state_ir
  | ClauseAnchorProductStep of product_step_ir
[@@deriving yojson]

type generated_clause_ir = {
  origin : generated_clause_origin;
  anchor : generated_clause_anchor_ir;
  hypotheses : clause_fact_ir list;
  conclusions : clause_fact_ir list;
}
[@@deriving yojson]

type relational_clause_fact_desc_ir =
  | RelFactProgramState of Ast.ident
  | RelFactGuaranteeState of int
  | RelFactPhaseFormula of Ast.ltl
  | RelFactFormula of Ast.ltl
  | RelFactFalse
[@@deriving yojson]

type relational_clause_fact_ir = {
  time : clause_time_ir;
  desc : relational_clause_fact_desc_ir;
}
[@@deriving yojson]

type relational_generated_clause_ir = {
  origin : generated_clause_origin;
  anchor : generated_clause_anchor_ir;
  hypotheses : relational_clause_fact_ir list;
  conclusions : relational_clause_fact_ir list;
}
[@@deriving yojson]

type instance_relation_ir =
  | InstanceUserInvariant of {
      instance_name : Ast.ident;
      callee_node_name : Ast.ident;
      invariant_id : Ast.ident;
      invariant_expr : Ast.hexpr;
    }
  | InstanceStateInvariant of {
      instance_name : Ast.ident;
      callee_node_name : Ast.ident;
      state_name : Ast.ident;
      is_eq : bool;
      formula : Ast.ltl;
    }
  | InstanceDelayHistoryLink of {
      instance_name : Ast.ident;
      callee_node_name : Ast.ident;
      caller_output : Ast.ident;
      callee_input : Ast.ident;
      callee_pre_name : Ast.ident option;
    }
  | InstanceDelayCallerPreLink of {
      caller_output : Ast.ident;
      caller_pre_name : Ast.ident;
    }
[@@deriving yojson]

type call_port_role =
  | CallInputPort
  | CallOutputPort
  | CallStatePort
[@@deriving yojson]

type call_port_ir = {
  port_name : Ast.ident;
  role : call_port_role;
}
[@@deriving yojson]

type call_binding_kind =
  | BindActualInput
  | BindActualOutput
  | BindInstancePreState
  | BindInstancePostState
[@@deriving yojson]

type call_binding_ir = {
  binding_kind : call_binding_kind;
  local_name : Ast.ident;
  remote_name : Ast.ident;
}
[@@deriving yojson]

type call_fact_kind =
  | CallEntryFact
  | CallTransitionFact
  | CallExportedPostFact
[@@deriving yojson]

type call_fact_ir = {
  fact_kind : call_fact_kind;
  fact : clause_fact_ir;
}
[@@deriving yojson]

type callee_summary_case_ir = {
  case_name : string;
  entry_facts : call_fact_ir list;
  transition_facts : call_fact_ir list;
  exported_post_facts : call_fact_ir list;
}
[@@deriving yojson]

type callee_tick_abi_ir = {
  callee_node_name : Ast.ident;
  input_ports : call_port_ir list;
  output_ports : call_port_ir list;
  state_ports : call_port_ir list;
  cases : callee_summary_case_ir list;
}
[@@deriving yojson]

type node_signature_ir = {
  node_name : Ast.ident;
  inputs : Ast.vdecl list;
  outputs : Ast.vdecl list;
  locals : Ast.vdecl list;
  instances : (Ast.ident * Ast.ident) list;
  states : Ast.ident list;
  init_state : Ast.ident;
}
[@@deriving yojson]

type call_site_instantiation_ir = {
  instance_name : Ast.ident;
  call_site_id : string;
  callee_node_name : Ast.ident;
  bindings : call_binding_ir list;
}
[@@deriving yojson]

type node_ir = {
  reactive_program : reactive_program_ir;
  assume_automaton : safety_automaton_ir;
  guarantee_automaton : safety_automaton_ir;
  initial_product_state : product_state_ir;
  product_states : product_state_ir list;
  product_steps : product_step_ir list;
  product_coverage : product_coverage_ir;
  historical_generated_clauses : generated_clause_ir list;
  eliminated_generated_clauses : generated_clause_ir list;
  symbolic_generated_clauses : relational_generated_clause_ir list;
  instance_relations : instance_relation_ir list;
  callee_tick_abis : callee_tick_abi_ir list;
  call_site_instantiations : call_site_instantiation_ir list;
  (* Ghost locals added by the pre_k instrumentation pass. *)
  ghost_locals : Ast.vdecl list;
}
[@@deriving yojson]

type exported_node_summary_ir = {
  signature : node_signature_ir;
  normalized_ir : node_ir;
  tick_summary : callee_tick_abi_ir;
  user_invariants : Ast.invariant_user list;
  state_invariants : Ast.invariant_state_rel list;
  coherency_goals : Ast.ltl_o list;
  pre_k_map : (Ast.hexpr * Support.pre_k_info) list;
  delay_spec : (Ast.ident * Ast.ident) option;
  (* LTL specifications — needed to reconstruct the runtime view without OBC+. *)
  assumes : Ast.ltl list;
  guarantees : Ast.ltl list;
}
[@@deriving yojson]

let phase_state_case_name ~(prog_state : Ast.ident) ~(guarantee_state : int) : string =
  Printf.sprintf "phase_case_%s_g%d" (String.lowercase_ascii prog_state) guarantee_state

let phase_step_case_stem (step : product_step_ir) : string =
  Printf.sprintf "%s_to_%s_a%d_%d_g%d_%d"
    (String.lowercase_ascii step.src.prog_state)
    (String.lowercase_ascii step.dst.prog_state)
    step.src.assume_state_index step.dst.assume_state_index
    step.src.guarantee_state_index step.dst.guarantee_state_index

let phase_step_pre_case_name (step : product_step_ir) : string =
  "phase_pre_" ^ phase_step_case_stem step

let phase_step_post_case_name (step : product_step_ir) : string =
  "phase_post_" ^ phase_step_case_stem step

let fo_of_iexpr (e : iexpr) : ltl = iexpr_to_fo_with_atoms [] e

let automaton_guard_fo ~(atom_map_exprs : (ident * iexpr) list) (g : Automaton_types.guard) : ltl =
  let recovered = Automata_atoms.recover_guard_fo atom_map_exprs g in
  let simplified = Fo_simplifier.simplify_fo recovered in
  match (g, simplified) with
  | [], _ -> LFalse
  | _ :: _, LFalse -> recovered
  | _ -> simplified

type lit = { var : ident; cst : string; is_pos : bool }

let lit_of_rel (h1 : hexpr) (r : relop) (h2 : hexpr) : lit option =
  let mk ?(is_pos = true) v c = Some { var = v; cst = c; is_pos } in
  match (h1, r, h2) with
  | HNow a, REq, HNow b -> begin
      match (a.iexpr, b.iexpr) with
      | IVar v, ILitInt i -> mk v (string_of_int i)
      | ILitInt i, IVar v -> mk v (string_of_int i)
      | IVar v, ILitBool bb -> mk v (if bb then "true" else "false")
      | ILitBool bb, IVar v -> mk v (if bb then "true" else "false")
      | ILitBool bb, _ -> mk (Support.string_of_iexpr b) (if bb then "true" else "false")
      | _, ILitBool bb -> mk (Support.string_of_iexpr a) (if bb then "true" else "false")
      | _ -> None
    end
  | HNow a, RNeq, HNow b -> begin
      match (a.iexpr, b.iexpr) with
      | IVar v, ILitInt i -> mk ~is_pos:false v (string_of_int i)
      | ILitInt i, IVar v -> mk ~is_pos:false v (string_of_int i)
      | IVar v, ILitBool bb -> mk ~is_pos:false v (if bb then "true" else "false")
      | ILitBool bb, IVar v -> mk ~is_pos:false v (if bb then "true" else "false")
      | ILitBool bb, _ ->
          mk ~is_pos:false (Support.string_of_iexpr b) (if bb then "true" else "false")
      | _, ILitBool bb -> mk ~is_pos:false (Support.string_of_iexpr a) (if bb then "true" else "false")
      | _ -> None
    end
  | _ -> None

let rec conj_lits (f : ltl) : lit list option =
  match f with
  | LTrue -> Some []
  | LAtom (FRel (h1, r, h2)) -> Option.map (fun l -> [ l ]) (lit_of_rel h1 r h2)
  | LNot (LAtom (FRel (h1, REq, h2))) ->
      Option.map (fun l -> [ { l with is_pos = false } ]) (lit_of_rel h1 REq h2)
  | LAnd (a, b) -> begin
      match (conj_lits a, conj_lits b) with
      | Some la, Some lb -> Some (la @ lb)
      | _ -> None
    end
  | _ -> None

let disj_conjs (f : ltl) : lit list list option =
  let rec go = function LOr (a, b) -> go a @ go b | x -> [ x ] in
  let xs = go f |> List.map conj_lits in
  List.fold_right
    (fun x acc -> Option.bind x (fun v -> Option.map (fun r -> v :: r) acc))
    xs (Some [])

let lits_consistent (a : lit list) (b : lit list) : bool =
  let pos = Hashtbl.create 16 in
  let neg = Hashtbl.create 16 in
  let add_lit l =
    if l.is_pos then (
      let prev = Hashtbl.find_opt pos l.var |> Option.value ~default:[] in
      if not (List.mem l.cst prev) then Hashtbl.replace pos l.var (l.cst :: prev))
    else (
      let prev = Hashtbl.find_opt neg l.var |> Option.value ~default:[] in
      if not (List.mem l.cst prev) then Hashtbl.replace neg l.var (l.cst :: prev))
  in
  List.iter add_lit (a @ b);
  let ok = ref true in
  Hashtbl.iter
    (fun v vals ->
      let unique_vals = List.sort_uniq String.compare vals in
      let neg_vals =
        Hashtbl.find_opt neg v |> Option.value ~default:[] |> List.sort_uniq String.compare
      in
      if List.length unique_vals > 1 then ok := false;
      if List.exists (fun c -> List.mem c neg_vals) unique_vals then ok := false)
    pos;
  !ok

let fo_overlap_conservative (a : ltl) (b : ltl) : bool =
  match (disj_conjs a, disj_conjs b) with
  | Some da, Some db ->
      List.exists (fun ca -> List.exists (fun cb -> lits_consistent ca cb) db) da
  | _ -> true

let guards_may_overlap (a : ltl) (b : ltl) : bool =
  match Fo_simplifier.simplify_fo (LAnd (a, b)) with
  | LFalse -> false
  | _ -> fo_overlap_conservative a b

let product_state_of_pt (st : PT.product_state) : product_state_ir =
  {
    prog_state = st.prog_state;
    assume_state_index = st.assume_state;
    guarantee_state_index = st.guarantee_state;
  }

let product_step_kind_of_pt = function
  | PT.Safe -> StepSafe
  | PT.Bad_assumption -> StepBadAssumption
  | PT.Bad_guarantee -> StepBadGuarantee

let is_live_state ~(analysis : Product_build.analysis) (st : PT.product_state) : bool =
  st.assume_state <> analysis.assume_bad_idx && st.guarantee_state <> analysis.guarantee_bad_idx

let string_of_role = function Assume -> "assume" | Guarantee -> "guarantee"

let string_of_step_kind = function
  | StepSafe -> "safe"
  | StepBadAssumption -> "bad_assumption"
  | StepBadGuarantee -> "bad_guarantee"

let string_of_step_origin = function
  | StepFromExplicitExploration -> "explicit"
  | StepFromFallbackSynthesis -> "fallback"

let string_of_product_coverage = function
  | CoverageEmpty -> "empty"
  | CoverageExplicit -> "explicit"
  | CoverageFallback -> "fallback"

let has_effective_product_coverage (ir : node_ir) : bool = ir.product_coverage <> CoverageEmpty

let pre_k_locals_of_ast (n : Ast.node) : Ast.vdecl list =
  let existing = List.map (fun (v : Ast.vdecl) -> v.vname) n.semantics.sem_locals in
  build_pre_k_infos n
  |> List.fold_left
       (fun acc (_, info) ->
         if List.exists
              (fun (existing_info : Support.pre_k_info) ->
                existing_info.Support.expr = info.Support.expr
                && existing_info.Support.names = info.Support.names)
              acc
         then
           acc
         else acc @ [ info ])
       []
  |> List.concat_map (fun info ->
         List.filter_map
           (fun name ->
             if List.mem name existing then None else Some { Ast.vname = name; vty = info.vty })
           info.names)

let node_signature_of_ast (n : Ast.node) : node_signature_ir =
  let sem = n.semantics in
  {
    node_name = sem.sem_nname;
    inputs = sem.sem_inputs;
    outputs = sem.sem_outputs;
    locals = sem.sem_locals @ pre_k_locals_of_ast n;
    instances = sem.sem_instances;
    states = sem.sem_states;
    init_state = sem.sem_init_state;
  }

let string_of_clause_origin = function
  | OriginSourceProductSummary -> "source/product_summary"
  | OriginPhaseStepPreSummary -> "phase/step_pre_summary"
  | OriginPhaseStepSummary -> "phase/step_summary"
  | OriginSafety -> "safety"
  | OriginInitNodeInvariant -> "init/node_inv"
  | OriginInitAutomatonCoherence -> "init/automaton"
  | OriginPropagationNodeInvariant -> "propagation/node_inv"
  | OriginPropagationAutomatonCoherence -> "propagation/automaton"

let string_of_clause_time = function
  | CurrentTick -> "current"
  | PreviousTick -> "previous"
  | StepTickContext -> "step_ctx"

let string_of_call_port_role = function
  | CallInputPort -> "input"
  | CallOutputPort -> "output"
  | CallStatePort -> "state"

let string_of_call_binding_kind = function
  | BindActualInput -> "actual_input"
  | BindActualOutput -> "actual_output"
  | BindInstancePreState -> "instance_pre"
  | BindInstancePostState -> "instance_post"

let string_of_call_fact_kind = function
  | CallEntryFact -> "entry"
  | CallTransitionFact -> "transition"
  | CallExportedPostFact -> "exported_post"

let string_of_clause_fact_desc = function
  | FactProgramState st -> "st = " ^ st
  | FactGuaranteeState idx -> "guarantee_state = " ^ string_of_int idx
  | FactPhaseFormula f -> "phase(" ^ string_of_ltl f ^ ")"
  | FactFormula f -> string_of_ltl f
  | FactFalse -> "false"

let string_of_relational_clause_fact_desc = function
  | RelFactProgramState st -> "st = " ^ st
  | RelFactGuaranteeState idx -> "guarantee_state = " ^ string_of_int idx
  | RelFactPhaseFormula f -> "phase(" ^ string_of_ltl f ^ ")"
  | RelFactFormula f -> string_of_ltl f
  | RelFactFalse -> "false"

let string_of_clause_fact (fact : clause_fact_ir) =
  Printf.sprintf "%s:%s" (string_of_clause_time fact.time) (string_of_clause_fact_desc fact.desc)

let string_of_relational_clause_fact (fact : relational_clause_fact_ir) =
  Printf.sprintf "%s:%s" (string_of_clause_time fact.time)
    (string_of_relational_clause_fact_desc fact.desc)

let string_of_call_fact (fact : call_fact_ir) =
  Printf.sprintf "%s:%s" (string_of_call_fact_kind fact.fact_kind) (string_of_clause_fact fact.fact)

let string_of_product_state (st : product_state_ir) =
  Printf.sprintf "(P=%s, A=%d, G=%d)" st.prog_state st.assume_state_index
    st.guarantee_state_index

let build_source_summary_clauses ~(node : Abs.node) ~(analysis : Product_build.analysis) ~(steps : product_step_ir list) :
    generated_clause_ir list =
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
    | LNot inner -> LNot (normalize_source_summary inner)
    | LAnd (a, b) -> LAnd (normalize_source_summary a, normalize_source_summary b)
    | LOr (a, b) -> LOr (normalize_source_summary a, normalize_source_summary b)
    | LImp (a, b) -> LImp (normalize_source_summary a, normalize_source_summary b)
    | LTrue | LFalse | LAtom _ | LX _ | LG _ | LW _ -> f
  in
  let term_or a b = normalize_source_summary (LOr (a, b)) in
  let term_and a b = normalize_source_summary (LAnd (a, b)) in
  let term_not a = normalize_source_summary (LNot a) in
  let same_product_state (a : product_state_ir) (b : product_state_ir) =
    a.prog_state = b.prog_state
    && a.assume_state_index = b.assume_state_index
    && a.guarantee_state_index = b.guarantee_state_index
  in
  (* Collect destination states reachable via safe steps.
     For each such destination state, the guard on the incoming safe automaton edge
     is the exact condition that y_NEW satisfied in the previous step to reach this state.
     Since y is a state variable, y_OLD in the current step equals that y_NEW.
     Therefore the disjunction of incoming safe-edge guards is a valid pre-state invariant
     for y when the automaton is in this destination state. *)
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
           |> List.filter (fun step ->
                  same_product_state step.dst dst && step.step_kind = StepSafe)
           |> List.map (fun step -> step.guarantee_edge.guard)
           |> List.filter (fun fo -> not (fo_mentions_current_input fo))
           |> List.sort_uniq Stdlib.compare
         in
         match safe_cases with
         | [] -> None
         | safe_case :: rest ->
             let pre_invariant =
               List.fold_left (fun acc fo -> LOr (acc, fo)) safe_case rest
               |> normalize_source_summary
             in
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
                   [
                     current (FactPhaseFormula pre_invariant);
                     current (FactFormula pre_invariant);
                   ];
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
           then Some (automaton_guard_fo ~atom_map_exprs:analysis.guarantee_atom_map_exprs guard_raw)
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
                     [
                       current (FactPhaseFormula phase_formula);
                       current (FactFormula phase_formula);
                     ];
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
    (fun prog_state entries ->
      let entries = List.sort (fun (g1, _, _) (g2, _, _) -> Int.compare g1 g2) entries in
      let _prog_state = prog_state in
      let _covered, () =
        List.fold_left
          (fun (covered_opt, ()) (gidx, raw_fo, key) ->
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
            let _gidx = gidx in
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
             begin
               match Hashtbl.find_opt exclusive_formula_table key with
               | None -> clause
               | Some phase_formula ->
                   {
                     clause with
                     conclusions =
                       [
                         current (FactPhaseFormula phase_formula);
                         current (FactFormula phase_formula);
                       ];
                   }
             end)

let string_of_edge (edge : automaton_edge_ir) =
  Printf.sprintf "%d -> %d : %s" edge.src_index edge.dst_index (string_of_ltl edge.guard)

let build_reactive_program ~(node_name : Ast.ident) ~(node : Abs.node) : reactive_program_ir =
  let transitions =
    List.map
      (fun (t : Abs.transition) ->
        {
          src_state = t.src;
          dst_state = t.dst;
          guard =
            (match t.guard with
            | None -> LTrue
            | Some g -> fo_of_iexpr g |> Fo_simplifier.simplify_fo);
          guard_iexpr = t.guard;
          requires = t.requires;
          ensures = t.ensures;
          ghost_stmts = t.attrs.ghost;
          body_stmts = t.body;
          instrumentation_stmts = t.attrs.instrumentation;
        })
      node.trans
  in
  {
    node_name;
    init_state = node.semantics.sem_init_state;
    states = node.semantics.sem_states;
    transitions;
  }

let build_automaton ~(role : automaton_role) ~(labels : string list) ~(bad_idx : int)
    ~(grouped_edges : PT.automaton_edge list) ~(atom_map_exprs : (Ast.ident * Ast.iexpr) list) :
    safety_automaton_ir =
  let edges =
    List.map
      (fun ((src, guard_raw, dst) : PT.automaton_edge) ->
        {
          src_index = src;
          dst_index = dst;
          guard = automaton_guard_fo ~atom_map_exprs guard_raw;
        })
      grouped_edges
  in
  {
    role;
    initial_state_index = 0;
    bad_state_index = if bad_idx < 0 then None else Some bad_idx;
    state_labels = List.mapi (fun i lbl -> (i, lbl)) labels;
    edges;
  }

let build_product_step (step : PT.product_step) : product_step_ir =
  {
    src = product_state_of_pt step.src;
    dst = product_state_of_pt step.dst;
    program_transition = (step.prog_transition.src, step.prog_transition.dst);
    program_guard = step.prog_guard;
    assume_edge =
      (let src, _guard, dst = step.assume_edge in
       { src_index = src; dst_index = dst; guard = step.assume_guard });
    guarantee_edge =
      (let src, _guard, dst = step.guarantee_edge in
       { src_index = src; dst_index = dst; guard = step.guarantee_guard });
    step_kind = product_step_kind_of_pt step.step_class;
    step_origin = StepFromExplicitExploration;
  }

let invariant_formula_for_state ~(node : Abs.node) (state_name : Ast.ident) : Ast.ltl option =
  let formulas =
    node.specification.spec_invariants_state_rel
    |> List.filter_map (fun (inv : Ast.invariant_state_rel) ->
           if (inv.is_eq && inv.state = state_name) || ((not inv.is_eq) && inv.state <> state_name)
           then Some inv.formula
           else None)
  in
  match formulas with
  | [] -> None
  | hd :: tl -> Some (List.fold_left (fun acc fo -> Ast.LAnd (acc, fo)) hd tl)

type current_const =
  | CInt of int
  | CBool of bool

type current_constraint_env = {
  parent : (Ast.ident, Ast.ident) Hashtbl.t;
  const_of_root : (Ast.ident, current_const) Hashtbl.t;
  forbids_of_root : (Ast.ident, current_const list) Hashtbl.t;
}

let empty_current_constraint_env () =
  {
    parent = Hashtbl.create 16;
    const_of_root = Hashtbl.create 16;
    forbids_of_root = Hashtbl.create 16;
  }

let rec find_root env v =
  match Hashtbl.find_opt env.parent v with
  | None ->
      Hashtbl.replace env.parent v v;
      v
  | Some p when p = v -> v
  | Some p ->
      let root = find_root env p in
      Hashtbl.replace env.parent v root;
      root

let const_equal a b =
  match (a, b) with
  | CInt x, CInt y -> x = y
  | CBool x, CBool y -> Bool.equal x y
  | _ -> false

let add_forbid env root c =
  let prev = Hashtbl.find_opt env.forbids_of_root root |> Option.value ~default:[] in
  if List.exists (const_equal c) prev then ()
  else Hashtbl.replace env.forbids_of_root root (c :: prev)

let root_forbids env root c =
  Hashtbl.find_opt env.forbids_of_root root
  |> Option.value ~default:[]
  |> List.exists (const_equal c)

let assign_const env root c =
  match Hashtbl.find_opt env.const_of_root root with
  | Some existing when not (const_equal existing c) -> false
  | Some _ -> not (root_forbids env root c)
  | None ->
      if root_forbids env root c then false
      else (
        Hashtbl.replace env.const_of_root root c;
        true)

let merge_roots env r1 r2 =
  if r1 = r2 then true
  else
    let c1 = Hashtbl.find_opt env.const_of_root r1 in
    let c2 = Hashtbl.find_opt env.const_of_root r2 in
    match (c1, c2) with
    | Some a, Some b when not (const_equal a b) -> false
    | _ ->
        Hashtbl.replace env.parent r2 r1;
        begin
          match c1 with
          | Some _ -> ()
          | None -> Option.iter (fun c -> Hashtbl.replace env.const_of_root r1 c) c2
        end;
        let forbids =
          (Hashtbl.find_opt env.forbids_of_root r1 |> Option.value ~default:[])
          @ (Hashtbl.find_opt env.forbids_of_root r2 |> Option.value ~default:[])
        in
        Hashtbl.replace env.forbids_of_root r1 forbids;
        begin
          match Hashtbl.find_opt env.const_of_root r1 with
          | Some c when root_forbids env r1 c -> false
          | _ -> true
        end

let clone_constraint_env env =
  let copy_tbl tbl =
    let out = Hashtbl.create (Hashtbl.length tbl * 2 + 1) in
    Hashtbl.iter (fun k v -> Hashtbl.replace out k v) tbl;
    out
  in
  {
    parent = copy_tbl env.parent;
    const_of_root = copy_tbl env.const_of_root;
    forbids_of_root = copy_tbl env.forbids_of_root;
  }

let current_const_of_iexpr (e : Ast.iexpr) : current_const option =
  match e.iexpr with
  | Ast.ILitInt n -> Some (CInt n)
  | Ast.ILitBool b -> Some (CBool b)
  | _ -> None

let current_var_of_hexpr = function
  | Ast.HNow { iexpr = Ast.IVar v; _ } -> Some v
  | _ -> None

let current_const_of_hexpr = function
  | Ast.HNow e -> current_const_of_iexpr e
  | _ -> None

let add_current_atom env ~(negated : bool) (fo : Ast.fo) : bool option =
  match fo with
  | Ast.FRel (h1, Ast.REq, h2) -> begin
      match
        ( current_var_of_hexpr h1,
          current_var_of_hexpr h2,
          current_const_of_hexpr h1,
          current_const_of_hexpr h2 )
      with
      | Some v, _, _, Some c ->
          let root = find_root env v in
          if negated then (
            add_forbid env root c;
            match Hashtbl.find_opt env.const_of_root root with
            | Some assigned when const_equal assigned c -> Some false
            | _ -> Some true)
          else Some (assign_const env root c)
      | _, Some v, Some c, _ ->
          let root = find_root env v in
          if negated then (
            add_forbid env root c;
            match Hashtbl.find_opt env.const_of_root root with
            | Some assigned when const_equal assigned c -> Some false
            | _ -> Some true)
          else Some (assign_const env root c)
      | Some v1, Some v2, _, _ when not negated ->
          Some (merge_roots env (find_root env v1) (find_root env v2))
      | _ -> None
    end
  | _ -> None

let rec current_formula_maybe_satisfiable env (fo : Ast.ltl) : bool =
  match fo with
  | Ast.LTrue -> true
  | Ast.LFalse -> false
  | Ast.LAtom atom -> begin
      match add_current_atom env ~negated:false atom with
      | Some b -> b
      | None -> true
    end
  | Ast.LNot (Ast.LAtom atom) -> begin
      match add_current_atom env ~negated:true atom with
      | Some b -> b
      | None -> true
    end
  | Ast.LNot inner -> not (current_formula_maybe_satisfiable env inner)
  | Ast.LAnd (a, b) ->
      current_formula_maybe_satisfiable env a && current_formula_maybe_satisfiable env b
  | Ast.LOr (a, b) ->
      let env_left = clone_constraint_env env in
      current_formula_maybe_satisfiable env_left a || current_formula_maybe_satisfiable env b
  | Ast.LImp _ | Ast.LX _ | Ast.LG _ | Ast.LW _ -> true

let is_feasible_product_step ~(node : Abs.node) ~(analysis : Product_build.analysis)
    (step : product_step_ir) : bool =
  (* The explicit exploration has already applied conservative overlap checks
     on program/assumption/guarantee guards. Re-simplifying the recovered FO
     guards here is unsound for kernel-clause generation: some temporal guards
     collapse to [false] after atom recovery even though the original product
     step was kept as potentially live. Keep the explicit step whenever its
     source is live and let the recovered hypotheses appear in the emitted
     clause.

     One additional structural filter is safe and useful: if the destination
     state's declared invariants already contradict the recovered guarantee
     guard, the product step cannot describe a realizable post-state phase and
     only pollutes downstream proof obligations. This uses only exported
     state invariants, not execution-level instrumentation. *)
  let src_live =
    is_live_state ~analysis
    {
      PT.prog_state = step.src.prog_state;
      assume_state = step.src.assume_state_index;
      guarantee_state = step.src.guarantee_state_index;
    }
  in
  src_live
  &&
  match invariant_formula_for_state ~node step.dst.prog_state with
  | None -> true
  | Some dst_inv ->
      current_formula_maybe_satisfiable
        (empty_current_constraint_env ())
        (Ast.LAnd (step.guarantee_edge.guard, dst_inv))

let synthesize_fallback_product_steps ~(node : Abs.node) ~(analysis : Product_build.analysis)
    ~(live_states : PT.product_state list) : product_step_ir list =
  let live_states = List.sort_uniq PT.compare_state live_states in
  let assume_edges =
    List.map
      (fun ((src, guard_raw, dst) : PT.automaton_edge) ->
        (src, dst, automaton_guard_fo ~atom_map_exprs:analysis.assume_atom_map_exprs guard_raw))
      analysis.assume_grouped_edges
  in
  let guarantee_edges =
    List.map
      (fun ((src, guard_raw, dst) : PT.automaton_edge) ->
        (src, dst, automaton_guard_fo ~atom_map_exprs:analysis.guarantee_atom_map_exprs guard_raw))
      analysis.guarantee_grouped_edges
  in
  let matching_edges edges src dst =
    edges
    |> List.filter_map (fun (s, d, g) -> if s = src && d = dst then Some g else None)
    |> List.sort_uniq Stdlib.compare
  in
  node.trans
  |> List.concat_map (fun (t : Abs.transition) ->
         let program_guard =
           match t.guard with
           | None -> LTrue
           | Some g -> Fo_simplifier.simplify_fo (fo_of_iexpr g)
         in
         live_states
         |> List.filter (fun (st : PT.product_state) -> st.prog_state = t.src)
         |> List.concat_map (fun (src : PT.product_state) ->
                live_states
                |> List.filter (fun (st : PT.product_state) -> st.prog_state = t.dst)
                |> List.filter_map (fun (dst : PT.product_state) ->
                       let assume_guards =
                         matching_edges assume_edges src.assume_state dst.assume_state
                       in
                       let guarantee_guards =
                         matching_edges guarantee_edges src.guarantee_state dst.guarantee_state
                       in
                       let assume_guard =
                         match assume_guards with
                         | [] -> None
                         | [ g ] -> Some g
                         | g :: gs -> Some (List.fold_left (fun acc x -> LOr (acc, x)) g gs)
                       in
                       let guarantee_guard =
                         match guarantee_guards with
                         | [] -> None
                         | [ g ] -> Some g
                         | g :: gs -> Some (List.fold_left (fun acc x -> LOr (acc, x)) g gs)
                       in
                       match (assume_guard, guarantee_guard) with
                       | Some ag, Some gg ->
                           let combined =
                             Fo_simplifier.simplify_fo (LAnd (program_guard, LAnd (ag, gg)))
                           in
                           if combined = LFalse then None
                           else
                             Some
                               {
                                 src = product_state_of_pt src;
                                 dst = product_state_of_pt dst;
                                 program_transition = (t.src, t.dst);
                                 program_guard;
                                 assume_edge =
                                   { src_index = src.assume_state; dst_index = dst.assume_state; guard = ag };
                                 guarantee_edge =
                                   {
                                     src_index = src.guarantee_state;
                                     dst_index = dst.guarantee_state;
                                     guard = gg;
                                   };
                                 step_kind = StepSafe;
                                 step_origin = StepFromFallbackSynthesis;
                               }
                       | _ -> None)))

let build_generated_clauses ~(node : Abs.node) ~(analysis : Product_build.analysis)
    ~(initial_state : product_state_ir) ~(steps : product_step_ir list) : generated_clause_ir list =
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
        Some
          (List.fold_left (fun acc fo -> LOr (acc, fo)) safe_case rest
          |> normalize_phase_summary)
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
        conclusions =
          current (FactProgramState initial_state.prog_state)
          :: invariants_for_state initial_state.prog_state;
      } : generated_clause_ir);
      ({
        origin = OriginInitAutomatonCoherence;
        anchor = ClauseAnchorProductState initial_state;
        hypotheses = [ current (FactProgramState initial_state.prog_state) ];
        conclusions = [ current (FactGuaranteeState initial_state.guarantee_state_index) ];
      } : generated_clause_ir);
    ]
  in
  let source_summary_clauses = build_source_summary_clauses ~node ~analysis ~steps in
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
              ]
              @ [
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
                conclusions =
                  current (FactProgramState step.dst.prog_state)
                  :: invariants_for_state step.dst.prog_state;
              } : generated_clause_ir);
              ({
                origin = OriginPropagationAutomatonCoherence;
                anchor = ClauseAnchorProductStep step;
                hypotheses = base_hypotheses;
                conclusions = [ current (FactGuaranteeState step.dst.guarantee_state_index) ];
              } : generated_clause_ir);
            ]
            @ phase_pre_clause
            @ phase_clause
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
                         ]
                         @ [
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
          (List.filter
             (fun (fact : relational_clause_fact_ir) -> fact.desc <> RelFactFormula LTrue)
             acc)
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
  let lower_all facts =
    List.filter_map (relationalize_clause_fact ~pre_k_map) facts
  in
  let hypotheses = lower_all clause.hypotheses in
  let conclusions = lower_all clause.conclusions in
  if conclusions = [] then []
  else
    expand_relational_hypotheses hypotheses
    |> List.filter_map (fun hypotheses ->
           match normalize_relational_hypotheses hypotheses with
           | None -> None
           | Some hypotheses -> Some { origin = clause.origin; anchor = clause.anchor; hypotheses; conclusions })

let lower_call_fact ~(pre_k_map : (Ast.hexpr * Support.pre_k_info) list) (fact : call_fact_ir) : call_fact_ir option =
  Option.map (fun lowered -> { fact with fact = lowered }) (lower_clause_fact ~pre_k_map fact.fact)

let lower_callee_summary_case ~(pre_k_map : (Ast.hexpr * Support.pre_k_info) list)
    (case : callee_summary_case_ir) : callee_summary_case_ir =
  let lower facts = List.filter_map (lower_call_fact ~pre_k_map) facts in
  {
    case with
    entry_facts = lower case.entry_facts;
    transition_facts = lower case.transition_facts;
    exported_post_facts = lower case.exported_post_facts;
  }

let lower_callee_tick_abi ~(pre_k_map : (Ast.hexpr * Support.pre_k_info) list) (abi : callee_tick_abi_ir) :
    callee_tick_abi_ir =
  { abi with cases = List.map (lower_callee_summary_case ~pre_k_map) abi.cases }

let current_fact (desc : clause_fact_desc_ir) : clause_fact_ir = { time = CurrentTick; desc }
let previous_fact (desc : clause_fact_desc_ir) : clause_fact_ir = { time = PreviousTick; desc }

let invariants_for_state ~(node : Abs.node) ~(time : clause_time_ir) (state_name : Ast.ident) :
    clause_fact_ir list =
  List.filter_map
    (fun inv ->
      if (inv.is_eq && inv.state = state_name) || ((not inv.is_eq) && inv.state <> state_name) then
        Some ({ time; desc = FactFormula inv.formula } : clause_fact_ir)
      else None)
    node.specification.spec_invariants_state_rel

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
          match t.guard with None -> [] | Some g -> [ { fact_kind = CallEntryFact; fact = current_fact (FactFormula (fo_of_iexpr g)) } ]
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
            ({ fact_kind = CallEntryFact; fact = current_fact (FactProgramState t.src) }
            :: guard)
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

let export_node_summary ~(node : Ast.node) ~(normalized_ir : node_ir) : exported_node_summary_ir =
  let pre_k_map = build_pre_k_infos node in
  {
    signature = node_signature_of_ast node;
    normalized_ir;
    tick_summary = lower_callee_tick_abi ~pre_k_map (callee_tick_abi_of_node ~node:(Abs.of_ast_node node));
    user_invariants = node.attrs.invariants_user;
    state_invariants = node.specification.spec_invariants_state_rel;
    coherency_goals = node.attrs.coherency_goals;
    pre_k_map;
    delay_spec = extract_delay_spec node.specification.spec_guarantees;
    assumes = node.specification.spec_assumes;
    guarantees = node.specification.spec_guarantees;
  }

let build_call_binding_pairs kind locals remotes =
  List.map2 (fun local_name remote_name -> { binding_kind = kind; local_name; remote_name }) locals remotes

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
  (* LOr(LTrue, eq) arises from OriginSourceProductSummary when an unconditional predecessor
     (e.g. the initial Aut0->Aut1 edge) is combined with the self-loop equation guard.
     The self-loop guard is the useful part for output-history inference. *)
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
                  output_history_links_of_resolved_callee ~nodes ~external_summaries callee
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
          compose_delay_relations_in_stmts ~nodes ~external_summaries ~instance_map ~slots_by_var env
            then_branch
        in
        let rels_else, env_else =
          compose_delay_relations_in_stmts ~nodes ~external_summaries ~instance_map ~slots_by_var env
            else_branch
        in
        (rels_then @ rels_else, merge_temporal_envs [ env_then; env_else ])
    | SMatch (_scrutinee, branches, default_branch) ->
        let branch_results =
          List.map
            (fun (_ctor, body) ->
              compose_delay_relations_in_stmts ~nodes ~external_summaries ~instance_map
                ~slots_by_var env body)
            branches
        in
        let default_rels, default_env =
          compose_delay_relations_in_stmts ~nodes ~external_summaries ~instance_map ~slots_by_var env
            default_branch
        in
        let all_rels =
          (branch_results |> List.concat_map fst) @ default_rels
        in
        let all_envs = (branch_results |> List.map snd) @ [ default_env ] in
        (all_rels, merge_temporal_envs all_envs)
  in
  List.fold_left
    (fun (rels_acc, env_acc) stmt ->
      let rels, env_next = compose_stmt env_acc stmt in
      (rels_acc @ rels, env_next))
    ([], env) stmts

and output_history_links_of_resolved_callee ~(nodes : Abs.node list)
    ~(external_summaries : exported_node_summary_ir list) (callee : resolved_callee) :
    Ast.ident list * Ast.ident list * (Ast.ident * Ast.ident * Ast.ident option) list =
  match callee with
  | Local callee_node ->
      let callee_ast = Abs.to_ast_node callee_node in
      let callee_pre_k_map = build_pre_k_infos callee_ast in
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
        infer_output_history_links ~output_names:(Ast_utils.output_names_of_node callee_ast)
          ~pre_k_map:callee_pre_k_map ~symbolic_clauses:normalized_ir.symbolic_generated_clauses )
  | External summary ->
      let summary_output_names = List.map (fun v -> v.vname) summary.signature.outputs in
      ( List.map (fun v -> v.vname) summary.signature.inputs,
        summary_output_names,
        infer_output_history_links ~output_names:summary_output_names ~pre_k_map:summary.pre_k_map
          ~symbolic_clauses:summary.normalized_ir.symbolic_generated_clauses )

and build_call_site_instantiations ~(nodes : Abs.node list)
    ~(external_summaries : exported_node_summary_ir list) ~(node : Abs.node) :
    call_site_instantiation_ir list =
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
              let output_bindings =
                build_call_binding_pairs BindActualOutput outs output_names
              in
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
              Some
                {
                  instance_name = inst_name;
                  call_site_id;
                  callee_node_name;
                  bindings = input_bindings @ output_bindings @ pre_state_bindings @ post_state_bindings;
                }))
    call_sites

and build_instance_relations ~(nodes : Abs.node list)
    ~(external_summaries : exported_node_summary_ir list) ~(node : Abs.node) :
    instance_relation_ir list =
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
                ~instance_map:node.semantics.sem_instances ~slots_by_var initial_temporal_env
                t.body))
    |> List.sort_uniq Stdlib.compare
  in
  invariant_relations @ delay_relations

and of_node_analysis ~(node_name : Ast.ident) ~(nodes : Abs.node list)
    ~(external_summaries : exported_node_summary_ir list) ~(node : Abs.node)
    ~(analysis : Product_build.analysis)
    : node_ir =
  let reactive_program = build_reactive_program ~node_name ~node in
  let assume_automaton =
    build_automaton ~role:Assume ~labels:analysis.assume_state_labels
      ~bad_idx:analysis.assume_bad_idx ~grouped_edges:analysis.assume_grouped_edges
      ~atom_map_exprs:analysis.assume_atom_map_exprs
  in
  let guarantee_automaton =
    build_automaton ~role:Guarantee ~labels:analysis.guarantee_state_labels
      ~bad_idx:analysis.guarantee_bad_idx ~grouped_edges:analysis.guarantee_grouped_edges
      ~atom_map_exprs:analysis.guarantee_atom_map_exprs
  in
  let initial_product_state = product_state_of_pt analysis.exploration.initial_state in
  let live_product_states =
    analysis.exploration.states |> List.filter (is_live_state ~analysis) |> List.sort_uniq PT.compare_state
  in
  let product_states = List.map product_state_of_pt live_product_states in
  let explicit_steps =
    List.map build_product_step analysis.exploration.steps
    |> List.filter (is_feasible_product_step ~node ~analysis)
  in
  let product_steps =
    if explicit_steps <> [] then explicit_steps
    else synthesize_fallback_product_steps ~node ~analysis ~live_states:live_product_states
  in
  let product_coverage =
    if explicit_steps <> [] then CoverageExplicit
    else if product_steps <> [] then CoverageFallback
    else CoverageEmpty
  in
  let historical_generated_clauses =
    build_generated_clauses ~node ~analysis ~initial_state:initial_product_state ~steps:product_steps
  in
  let pre_k_map = build_pre_k_infos (Abs.to_ast_node node) in
  let eliminated_generated_clauses =
    List.filter_map (lower_generated_clause ~pre_k_map) historical_generated_clauses
  in
  let symbolic_generated_clauses =
    List.concat_map (relationalize_generated_clause ~pre_k_map) eliminated_generated_clauses
  in
  let instance_relations = build_instance_relations ~nodes ~external_summaries ~node in
  let called_callee_names =
    collect_call_sites_with_paths node.trans
    |> List.filter_map (fun (_t, _path, inst_name, _args, _outs) ->
           List.assoc_opt inst_name node.semantics.sem_instances)
    |> List.sort_uniq String.compare
  in
  let callee_tick_abis =
    List.filter_map
      (fun callee_name ->
        match resolve_callee ~nodes ~external_summaries callee_name with
        | Some (Local callee_node) ->
            let callee_ast = Abs.to_ast_node callee_node in
            let callee_pre_k_map = build_pre_k_infos callee_ast in
            Some (lower_callee_tick_abi ~pre_k_map:callee_pre_k_map (callee_tick_abi_of_node ~node:callee_node))
        | Some (External summary) -> Some summary.tick_summary
        | None -> None)
      called_callee_names
  in
  let call_site_instantiations = build_call_site_instantiations ~nodes ~external_summaries ~node in
  let ghost_locals = pre_k_locals_of_ast (Abs.to_ast_node node) in
  {
    reactive_program;
    assume_automaton;
    guarantee_automaton;
    initial_product_state;
    product_states;
    product_steps;
    product_coverage;
    historical_generated_clauses;
    eliminated_generated_clauses;
    symbolic_generated_clauses;
    instance_relations;
    callee_tick_abis;
    call_site_instantiations;
    ghost_locals;
  }

let render_reactive_program (p : reactive_program_ir) : string list =
  let header =
    Printf.sprintf "reactive_program %s init=%s states=%d transitions=%d" p.node_name p.init_state
      (List.length p.states) (List.length p.transitions)
  in
  let states = List.map (fun st -> Printf.sprintf "  state %s" st) p.states in
  let transitions =
    List.map
      (fun t ->
        Printf.sprintf "  trans %s -> %s guard=%s" t.src_state t.dst_state (string_of_ltl t.guard))
      p.transitions
  in
  header :: (states @ transitions)

let render_automaton (a : safety_automaton_ir) : string list =
  let bad =
    match a.bad_state_index with None -> "none" | Some idx -> string_of_int idx
  in
  let header =
    Printf.sprintf "%s_automaton init=%d bad=%s states=%d edges=%d" (string_of_role a.role)
      a.initial_state_index bad (List.length a.state_labels) (List.length a.edges)
  in
  let states =
    List.map (fun (idx, lbl) -> Printf.sprintf "  state %d = %s" idx lbl) a.state_labels
  in
  let edges = List.map (fun edge -> "  edge " ^ string_of_edge edge) a.edges in
  header :: (states @ edges)

let render_generated_clause kind (clause : generated_clause_ir) : string =
  let subject =
    match clause.anchor with
    | ClauseAnchorProductState st -> string_of_product_state st
    | ClauseAnchorProductStep step ->
        Printf.sprintf "%s -> %s" (string_of_product_state step.src)
          (string_of_product_state step.dst)
  in
  let hyps = String.concat ", " (List.map string_of_clause_fact clause.hypotheses) in
  let concls = String.concat ", " (List.map string_of_clause_fact clause.conclusions) in
  Printf.sprintf "  %s %s on %s if [%s] then [%s]" kind
    (string_of_clause_origin clause.origin) subject hyps concls

let render_historical_clauses (ir : node_ir) : string list =
  List.map (render_generated_clause "historical_clause") ir.historical_generated_clauses

let render_eliminated_clauses (ir : node_ir) : string list =
  List.map (render_generated_clause "eliminated_clause") ir.eliminated_generated_clauses

let render_product (ir : node_ir) : string list =
  let header =
    Printf.sprintf "explicit_product initial=%s states=%d steps=%d historical=%d eliminated=%d symbolic=%d"
      (string_of_product_state ir.initial_product_state) (List.length ir.product_states)
      (List.length ir.product_steps) (List.length ir.historical_generated_clauses)
      (List.length ir.eliminated_generated_clauses)
      (List.length ir.symbolic_generated_clauses)
  in
  let coverage = Printf.sprintf "  coverage %s" (string_of_product_coverage ir.product_coverage) in
  let states =
    List.map (fun st -> "  pstate " ^ string_of_product_state st) ir.product_states
  in
  let steps =
    List.map
      (fun step ->
        Printf.sprintf
          "  pstep %s -- %s->%s / A[%d->%d] / G[%d->%d] --> %s [%s/%s]"
          (string_of_product_state step.src) (fst step.program_transition)
          (snd step.program_transition) step.assume_edge.src_index step.assume_edge.dst_index
          step.guarantee_edge.src_index step.guarantee_edge.dst_index
          (string_of_product_state step.dst) (string_of_step_kind step.step_kind)
          (string_of_step_origin step.step_origin))
      ir.product_steps
  in
  let historical_clauses = render_historical_clauses ir in
  let eliminated_clauses = render_eliminated_clauses ir in
  let symbolic_clauses =
    List.map
      (fun (clause : relational_generated_clause_ir) ->
        let subject =
          match clause.anchor with
          | ClauseAnchorProductState st -> string_of_product_state st
          | ClauseAnchorProductStep step ->
              Printf.sprintf "%s -> %s" (string_of_product_state step.src)
                (string_of_product_state step.dst)
        in
        let hyps = String.concat ", " (List.map string_of_relational_clause_fact clause.hypotheses) in
        let concls = String.concat ", " (List.map string_of_relational_clause_fact clause.conclusions) in
        Printf.sprintf "  symbolic_clause %s on %s if [%s] then [%s]"
          (string_of_clause_origin clause.origin) subject hyps concls)
      ir.symbolic_generated_clauses
  in
  let instance_relations =
    List.map
      (function
        | InstanceUserInvariant { instance_name; callee_node_name; invariant_id; _ } ->
            Printf.sprintf "  instance %s:%s user_invariant %s" instance_name callee_node_name
              invariant_id
        | InstanceStateInvariant { instance_name; callee_node_name; state_name; is_eq; _ } ->
            Printf.sprintf "  instance %s:%s state_%s %s" instance_name callee_node_name
              (if is_eq then "eq" else "neq") state_name
        | InstanceDelayHistoryLink
            { instance_name; callee_node_name; caller_output; callee_input; callee_pre_name } ->
            Printf.sprintf "  instance %s:%s delay_history %s <- old(%s)"
              instance_name callee_node_name caller_output
              (Option.value ~default:callee_input callee_pre_name)
        | InstanceDelayCallerPreLink { caller_output; caller_pre_name } ->
            Printf.sprintf "  instance delay_caller_pre %s <- %s" caller_output caller_pre_name)
      ir.instance_relations
  in
  header :: (coverage :: (states @ steps @ historical_clauses @ eliminated_clauses @ symbolic_clauses @ instance_relations))

let render_call_summary_section (ir : node_ir) : string list =
  let abi_header =
    Printf.sprintf "callee_tick_abis count=%d" (List.length ir.callee_tick_abis)
  in
  let abi_lines =
    List.concat_map
      (fun abi ->
        let ports label ports =
          List.map
            (fun port ->
              Printf.sprintf "    %s_port %s (%s)" label port.port_name
                (string_of_call_port_role port.role))
            ports
        in
        let cases =
          List.concat_map
            (fun (case : callee_summary_case_ir) ->
              let render_facts label facts =
                List.map
                  (fun fact -> Printf.sprintf "      %s %s" label (string_of_call_fact fact))
                  facts
              in
              ("    case " ^ case.case_name)
              :: (render_facts "entry" case.entry_facts
                 @ render_facts "transition" case.transition_facts
                 @ render_facts "exported" case.exported_post_facts))
            abi.cases
        in
        ("  callee_tick_abi " ^ abi.callee_node_name)
        :: (ports "input" abi.input_ports
           @ ports "output" abi.output_ports
           @ ports "state" abi.state_ports
           @ cases))
      ir.callee_tick_abis
  in
  let inst_header =
    Printf.sprintf "call_site_instantiations count=%d" (List.length ir.call_site_instantiations)
  in
  let inst_lines =
    List.concat_map
      (fun inst ->
        let bindings =
          List.map
            (fun binding ->
              Printf.sprintf "    binding %s %s -> %s"
                (string_of_call_binding_kind binding.binding_kind)
                binding.local_name binding.remote_name)
            inst.bindings
        in
        (Printf.sprintf "  call_site %s instance=%s callee=%s" inst.call_site_id inst.instance_name
           inst.callee_node_name)
        :: bindings)
      ir.call_site_instantiations
  in
  abi_header :: (abi_lines @ (inst_header :: inst_lines))

let render_call_summary_toy_example =
  let mk_fact fact_kind time desc = { fact_kind; fact = { time; desc } } in
  let mk_eq lhs rhs =
    LAtom (FRel (HNow (Ast_builders.mk_var lhs), REq, HNow (Ast_builders.mk_var rhs)))
  in
  let abi =
    {
      callee_node_name = "Delay";
      input_ports = [ { port_name = "x"; role = CallInputPort } ];
      output_ports = [ { port_name = "y"; role = CallOutputPort } ];
      state_ports = [ { port_name = "mem"; role = CallStatePort } ];
      cases =
        [
          {
            case_name = "tick";
            entry_facts = [];
            transition_facts =
              [
                mk_fact CallTransitionFact CurrentTick (FactFormula (mk_eq "y" "mem_pre"));
                mk_fact CallTransitionFact CurrentTick (FactFormula (mk_eq "mem_post" "x"));
              ];
            exported_post_facts =
              [ mk_fact CallExportedPostFact CurrentTick (FactFormula (mk_eq "mem_post" "x")) ];
          };
        ];
    }
  in
  let inst =
    {
      instance_name = "d";
      call_site_id = "toy.delay.call.1";
      callee_node_name = "Delay";
      bindings =
        [
          { binding_kind = BindActualInput; local_name = "a"; remote_name = "x" };
          { binding_kind = BindActualOutput; local_name = "b"; remote_name = "y" };
          { binding_kind = BindInstancePreState; local_name = "d_mem_pre"; remote_name = "mem" };
          { binding_kind = BindInstancePostState; local_name = "d_mem_post"; remote_name = "mem" };
        ];
    }
  in
  let ir =
    {
      reactive_program =
        { node_name = "toy"; init_state = "Init"; states = []; transitions = [] };
      assume_automaton =
        { role = Assume; initial_state_index = 0; bad_state_index = None; state_labels = []; edges = [] };
      guarantee_automaton =
        { role = Guarantee; initial_state_index = 0; bad_state_index = None; state_labels = []; edges = [] };
      initial_product_state = { prog_state = "Init"; assume_state_index = 0; guarantee_state_index = 0 };
      product_states = [];
      product_steps = [];
      product_coverage = CoverageEmpty;
      historical_generated_clauses = [];
      eliminated_generated_clauses = [];
      symbolic_generated_clauses = [];
      instance_relations = [];
      callee_tick_abis = [ abi ];
      call_site_instantiations = [ inst ];
      ghost_locals = [];
    }
  in
  ("-- Toy call summary ABI example --" :: render_call_summary_section ir)

let render_node_ir (ir : node_ir) : string list =
  [ "-- Kernel-compatible pipeline IR --" ]
  @ render_reactive_program ir.reactive_program
  @ render_automaton ir.assume_automaton
  @ render_automaton ir.guarantee_automaton
  @ render_product ir
  @ render_call_summary_section ir
  @ render_call_summary_toy_example
