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
  guard : Ast.fo;
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
  guard : Ast.fo;
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
  program_guard : Ast.fo;
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
  | FactFormula of Ast.fo
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
  | RelFactFormula of Ast.fo
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
      formula : Ast.fo;
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
  generated_clauses : generated_clause_ir list;
  relational_generated_clauses : relational_generated_clause_ir list;
  instance_relations : instance_relation_ir list;
  callee_tick_abis : callee_tick_abi_ir list;
  call_site_instantiations : call_site_instantiation_ir list;
}
[@@deriving yojson]

type exported_node_summary_ir = {
  signature : node_signature_ir;
  normalized_ir : node_ir;
  tick_summary : callee_tick_abi_ir;
  user_invariants : Ast.invariant_user list;
  state_invariants : Ast.invariant_state_rel list;
  coherency_goals : Ast.fo_o list;
  pre_k_map : (Ast.hexpr * Support.pre_k_info) list;
  delay_spec : (Ast.ident * Ast.ident) option;
}
[@@deriving yojson]

let fo_of_iexpr (e : iexpr) : fo = iexpr_to_fo_with_atoms [] e

let automaton_guard_fo ~(atom_map_exprs : (ident * iexpr) list) (g : Automaton_types.guard) : fo =
  let recovered = Automata_atoms.recover_guard_fo atom_map_exprs g in
  let simplified = Fo_simplifier.simplify_fo recovered in
  match (g, simplified) with
  | [], _ -> FFalse
  | _ :: _, FFalse -> recovered
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

let rec conj_lits (f : fo) : lit list option =
  match f with
  | FTrue -> Some []
  | FRel (h1, r, h2) -> Option.map (fun l -> [ l ]) (lit_of_rel h1 r h2)
  | FNot x -> begin
      match x with
      | FRel (h1, REq, h2) ->
          Option.map (fun l -> [ { l with is_pos = false } ]) (lit_of_rel h1 REq h2)
      | _ -> None
    end
  | FAnd (a, b) -> begin
      match (conj_lits a, conj_lits b) with
      | Some la, Some lb -> Some (la @ lb)
      | _ -> None
    end
  | _ -> None

let disj_conjs (f : fo) : lit list list option =
  let rec go = function FOr (a, b) -> go a @ go b | x -> [ x ] in
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

let fo_overlap_conservative (a : fo) (b : fo) : bool =
  match (disj_conjs a, disj_conjs b) with
  | Some da, Some db ->
      List.exists (fun ca -> List.exists (fun cb -> lits_consistent ca cb) db) da
  | _ -> true

let guards_may_overlap (a : fo) (b : fo) : bool =
  match Fo_simplifier.simplify_fo (FAnd (a, b)) with
  | FFalse -> false
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
  let existing = List.map (fun (v : Ast.vdecl) -> v.vname) n.locals in
  build_pre_k_infos n
  |> List.concat_map (fun (_, info) ->
         List.filter_map
           (fun name ->
             if List.mem name existing then None else Some { Ast.vname = name; vty = info.vty })
           info.names)

let node_signature_of_ast (n : Ast.node) : node_signature_ir =
  {
    node_name = n.nname;
    inputs = n.inputs;
    outputs = n.outputs;
    locals = n.locals @ pre_k_locals_of_ast n;
    instances = n.instances;
    states = n.states;
    init_state = n.init_state;
  }

let string_of_clause_origin = function
  | OriginSourceProductSummary -> "source/product_summary"
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
  | FactFormula f -> string_of_fo f
  | FactFalse -> "false"

let string_of_relational_clause_fact_desc = function
  | RelFactProgramState st -> "st = " ^ st
  | RelFactFormula f -> string_of_fo f
  | RelFactFalse -> "false"

let string_of_clause_fact (fact : clause_fact_ir) =
  Printf.sprintf "%s:%s" (string_of_clause_time fact.time) (string_of_clause_fact_desc fact.desc)

let string_of_call_fact (fact : call_fact_ir) =
  Printf.sprintf "%s:%s" (string_of_call_fact_kind fact.fact_kind) (string_of_clause_fact fact.fact)

let string_of_product_state (st : product_state_ir) =
  Printf.sprintf "(P=%s, A=%d, G=%d)" st.prog_state st.assume_state_index
    st.guarantee_state_index

let build_source_summary_clauses ~(node : Abs.node) ~(analysis : Product_build.analysis) ~(steps : product_step_ir list) :
    generated_clause_ir list =
  let _analysis = analysis in
  let ast_node = Abs.to_ast_node node in
  let current (desc : clause_fact_desc_ir) : clause_fact_ir = { time = CurrentTick; desc } in
  let input_names =
    ast_node.inputs |> List.map (fun (v : Ast.vdecl) -> v.vname) |> List.sort_uniq String.compare
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
  let rec fo_mentions_current_input (f : Ast.fo) =
    match f with
    | FTrue | FFalse -> false
    | FRel (a, _, b) -> hexpr_mentions_current_input a || hexpr_mentions_current_input b
    | FPred (_, hs) -> List.exists hexpr_mentions_current_input hs
    | FNot inner -> fo_mentions_current_input inner
    | FAnd (a, b) | FOr (a, b) | FImp (a, b) ->
        fo_mentions_current_input a || fo_mentions_current_input b
  in
  let rec normalize_source_summary (f : fo) : fo =
    match f with
    | FNot (FOr (FNot a, FNot b)) -> FAnd (normalize_source_summary a, normalize_source_summary b)
    | FNot inner -> FNot (normalize_source_summary inner)
    | FAnd (a, b) -> FAnd (normalize_source_summary a, normalize_source_summary b)
    | FOr (a, b) -> FOr (normalize_source_summary a, normalize_source_summary b)
    | FImp (a, b) -> FImp (normalize_source_summary a, normalize_source_summary b)
    | FTrue | FFalse | FRel _ | FPred _ -> f
  in
  let same_product_state (a : product_state_ir) (b : product_state_ir) =
    a.prog_state = b.prog_state
    && a.assume_state_index = b.assume_state_index
    && a.guarantee_state_index = b.guarantee_state_index
  in
  let bad_case_for_step (step : product_step_ir) =
    step.guarantee_edge.guard
  in
  let src_states =
    steps
    |> List.filter_map (fun (step : product_step_ir) ->
           match step.step_kind with
           | StepBadGuarantee -> Some step.src
           | StepSafe | StepBadAssumption -> None)
    |> List.sort_uniq Stdlib.compare
  in
  src_states
  |> List.filter_map (fun (src : product_state_ir) ->
         let bad_cases =
           steps
           |> List.filter (fun step ->
                  same_product_state step.src src && step.step_kind = StepBadGuarantee)
           |> List.map bad_case_for_step
           |> List.filter (fun fo -> not (fo_mentions_current_input fo))
           |> List.sort_uniq Stdlib.compare
         in
         match bad_cases with
         | [] -> None
         | bad_case :: rest ->
             let safe_summary =
               List.fold_left (fun acc fo -> FOr (acc, fo)) bad_case rest
               |> fun disj -> FNot disj
               |> normalize_source_summary
             in
             Some
               ({
                 origin = OriginSourceProductSummary;
                 anchor = ClauseAnchorProductState src;
                 hypotheses =
                   [
                     current (FactProgramState src.prog_state);
                     current (FactGuaranteeState src.guarantee_state_index);
                   ];
                 conclusions = [ current (FactFormula safe_summary) ];
               } : generated_clause_ir))

let string_of_edge (edge : automaton_edge_ir) =
  Printf.sprintf "%d -> %d : %s" edge.src_index edge.dst_index (string_of_fo edge.guard)

let build_reactive_program ~(node_name : Ast.ident) ~(node : Abs.node) : reactive_program_ir =
  let transitions =
    List.map
      (fun (t : Abs.transition) ->
        {
          src_state = t.src;
          dst_state = t.dst;
          guard =
            (match t.guard with
            | None -> FTrue
            | Some g -> fo_of_iexpr g |> Fo_simplifier.simplify_fo);
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

let is_feasible_product_step ~(analysis : Product_build.analysis) (step : product_step_ir) : bool =
  (* The explicit exploration has already applied conservative overlap checks
     on program/assumption/guarantee guards. Re-simplifying the recovered FO
     guards here is unsound for kernel-clause generation: some temporal guards
     collapse to [false] after atom recovery even though the original product
     step was kept as potentially live. Keep the explicit step whenever its
     source is live and let the recovered hypotheses appear in the emitted
     clause. *)
  is_live_state ~analysis
    {
      PT.prog_state = step.src.prog_state;
      assume_state = step.src.assume_state_index;
      guarantee_state = step.src.guarantee_state_index;
    }

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
           | None -> FTrue
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
                         | g :: gs -> Some (List.fold_left (fun acc x -> FOr (acc, x)) g gs)
                       in
                       let guarantee_guard =
                         match guarantee_guards with
                         | [] -> None
                         | [ g ] -> Some g
                         | g :: gs -> Some (List.fold_left (fun acc x -> FOr (acc, x)) g gs)
                       in
                       match (assume_guard, guarantee_guard) with
                       | Some ag, Some gg ->
                           let combined =
                             Fo_simplifier.simplify_fo (FAnd (program_guard, FAnd (ag, gg)))
                           in
                           if combined = FFalse then None
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
            [
              ({
                origin = OriginPropagationNodeInvariant;
                anchor = ClauseAnchorProductStep step;
                hypotheses =
                  [
                    previous (FactProgramState step.src.prog_state);
                    previous (FactGuaranteeState step.src.guarantee_state_index);
                    step_ctx (FactFormula step.program_guard);
                    step_ctx (FactFormula step.assume_edge.guard);
                    step_ctx (FactFormula step.guarantee_edge.guard);
                  ];
                conclusions = [ current (FactProgramState step.dst.prog_state) ];
              } : generated_clause_ir);
              ({
                origin = OriginPropagationAutomatonCoherence;
                anchor = ClauseAnchorProductStep step;
                hypotheses =
                  [
                    previous (FactProgramState step.src.prog_state);
                    previous (FactGuaranteeState step.src.guarantee_state_index);
                    step_ctx (FactFormula step.program_guard);
                    step_ctx (FactFormula step.assume_edge.guard);
                    step_ctx (FactFormula step.guarantee_edge.guard);
                  ];
                conclusions = [ current (FactGuaranteeState step.dst.guarantee_state_index) ];
              } : generated_clause_ir);
            ]
          else []
        in
        let safety =
          match step.step_kind with
          | StepBadGuarantee ->
              [
                ({
                  origin = OriginSafety;
                  anchor = ClauseAnchorProductStep step;
                  hypotheses =
                    [
                      previous (FactProgramState step.src.prog_state);
                      previous (FactGuaranteeState step.src.guarantee_state_index);
                      step_ctx (FactFormula step.program_guard);
                      step_ctx (FactFormula step.assume_edge.guard);
                      step_ctx (FactFormula step.guarantee_edge.guard);
                    ];
                  conclusions = [ current FactFalse ];
                } : generated_clause_ir);
              ]
          | StepSafe | StepBadAssumption -> []
        in
        propagation @ safety)
      steps
  in
  init_clauses @ source_summary_clauses @ step_clauses

let lower_clause_fact ~(pre_k_map : (Ast.hexpr * Support.pre_k_info) list) (fact : clause_fact_ir) :
    clause_fact_ir option =
  let lower_desc = function
    | FactProgramState _ as desc -> Some desc
    | FactGuaranteeState _ as desc -> Some desc
    | FactFalse -> Some FactFalse
    | FactFormula fo -> Option.map (fun fo' -> FactFormula fo') (lower_fo_pre_k ~pre_k_map fo)
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
      if List.exists (fun (fact : clause_fact_ir) -> fact.desc = FactFormula FFalse || fact.desc = FactFalse) hypotheses
      then None
      else Some { clause with hypotheses; conclusions }
  | _ -> None

let relationalize_clause_fact ~(pre_k_map : (Ast.hexpr * Support.pre_k_info) list)
    (fact : clause_fact_ir) : relational_clause_fact_ir option =
  let rel_desc = function
    | FactProgramState st -> Some (RelFactProgramState st)
    | FactFormula fo -> Option.map (fun fo' -> RelFactFormula fo') (lower_fo_pre_k ~pre_k_map fo)
    | FactFalse -> Some RelFactFalse
    | FactGuaranteeState _ -> None
  in
  Option.map (fun desc -> { time = fact.time; desc }) (rel_desc fact.desc)

let expand_relational_hypotheses (facts : relational_clause_fact_ir list) :
    relational_clause_fact_ir list list =
  let rec expand_one acc = function
    | [] -> [ List.rev acc ]
    | ({ desc = RelFactFormula (FOr (a, b)); _ } as fact) :: tl ->
        let left = { fact with desc = RelFactFormula (Fo_simplifier.simplify_fo a) } in
        let right = { fact with desc = RelFactFormula (Fo_simplifier.simplify_fo b) } in
        (expand_one (left :: acc) tl) @ expand_one (right :: acc) tl
    | fact :: tl -> expand_one (fact :: acc) tl
  in
  expand_one [] facts

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
    |> List.filter (fun hypotheses ->
           not
             (List.exists
                (fun (fact : relational_clause_fact_ir) ->
                  fact.desc = RelFactFormula FFalse || fact.desc = RelFactFalse)
                hypotheses))
    |> List.map (fun hypotheses -> { origin = clause.origin; anchor = clause.anchor; hypotheses; conclusions })

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
  let cases =
    List.mapi
      (fun idx (t : Abs.transition) ->
        let guard =
          match t.guard with None -> [] | Some g -> [ { fact_kind = CallEntryFact; fact = current_fact (FactFormula (fo_of_iexpr g)) } ]
        in
        let requires =
          List.map
            (fun fo_o -> { fact_kind = CallEntryFact; fact = current_fact (FactFormula fo_o.value) })
            t.requires
        in
        let transition_facts =
          { fact_kind = CallTransitionFact; fact = current_fact (FactProgramState t.dst) }
          :: List.map
               (fun fo_o ->
                 { fact_kind = CallTransitionFact; fact = current_fact (FactFormula fo_o.value) })
               t.ensures
        in
        let exported_post_facts =
          List.map
            (fun fact -> { fact_kind = CallExportedPostFact; fact })
            (invariants_for_state ~node ~time:CurrentTick t.dst)
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
    state_invariants = node.attrs.invariants_state_rel;
    coherency_goals = node.attrs.coherency_goals;
    pre_k_map;
    delay_spec = extract_delay_spec node.guarantees;
  }

let build_call_binding_pairs kind locals remotes =
  List.map2 (fun local_name remote_name -> { binding_kind = kind; local_name; remote_name }) locals remotes

let build_call_site_instantiations ~(nodes : Abs.node list)
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

let build_instance_relations ~(nodes : Abs.node list)
    ~(external_summaries : exported_node_summary_ir list) ~(node : Abs.node) :
    instance_relation_ir list =
  let n_ast = Abs.to_ast_node node in
  let pre_k_map = build_pre_k_infos n_ast in
  let pre_k_first_name_for v =
    List.find_map
      (fun (_, info) ->
        match (info.expr.iexpr, info.names) with
        | IVar x, name :: _ when x = v -> Some name
        | _ -> None)
      pre_k_map
  in
  let invariant_relations =
    List.concat_map
      (fun (inst_name, node_name) ->
        match resolve_callee ~nodes ~external_summaries node_name with
        | None -> []
        | Some callee ->
            let user_invariants, state_invariants =
              match callee with
              | Local inst_node -> (inst_node.attrs.invariants_user, inst_node.attrs.invariants_state_rel)
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
    collect_calls_trans_full n_ast.trans
    |> List.concat_map (fun (inst_name, args, outs) ->
           match List.assoc_opt inst_name node.semantics.sem_instances with
           | None -> []
           | Some callee_node_name -> (
               match resolve_callee ~nodes ~external_summaries callee_node_name with
               | None -> []
               | Some callee ->
                   let input_names, output_names, delay_spec, pre_k_map_inst =
                     match callee with
                     | Local callee_node ->
                         let callee_ast = Abs.to_ast_node callee_node in
                         ( Ast_utils.input_names_of_node callee_ast,
                           Ast_utils.output_names_of_node callee_ast,
                           extract_delay_spec callee_ast.guarantees,
                           build_pre_k_infos callee_ast )
                     | External summary ->
                         ( List.map (fun v -> v.vname) summary.signature.inputs,
                           List.map (fun v -> v.vname) summary.signature.outputs,
                           summary.delay_spec,
                           summary.pre_k_map )
                   in
                   match delay_spec with
                   | None -> []
                   | Some (out_name, in_name) ->
                       begin
                         match List.find_opt (( = ) in_name) input_names with
                         | None -> []
                         | Some _ ->
                             let callee_pre_name =
                               List.find_map
                                 (fun (_, info) ->
                                   match (info.expr.iexpr, info.names) with
                                   | IVar x, name :: _ when x = in_name -> Some name
                                   | _ -> None)
                                 pre_k_map_inst
                             in
                             let history_links =
                               match
                                 List.find_index (fun name -> name = out_name) output_names
                               with
                               | None -> []
                               | Some out_idx ->
                                   if out_idx >= List.length outs then []
                                   else
                                     [
                                       InstanceDelayHistoryLink
                                         {
                                           instance_name = inst_name;
                                           callee_node_name;
                                           caller_output = List.nth outs out_idx;
                                           callee_input = in_name;
                                           callee_pre_name;
                                         };
                                     ]
                             in
                             let caller_pre_links =
                               match
                                 List.assoc_opt in_name (List.combine input_names args)
                               with
                               | Some e -> (
                                   match e.iexpr with
                                   | IVar v -> (
                                       match pre_k_first_name_for v with
                                       | None -> []
                                       | Some caller_pre_name -> (
                                           match
                                             List.find_index (fun name -> name = out_name) output_names
                                           with
                                           | None -> []
                                           | Some out_idx ->
                                               if out_idx >= List.length outs then []
                                               else
                                                 [
                                                   InstanceDelayCallerPreLink
                                                     {
                                                       caller_output = List.nth outs out_idx;
                                                       caller_pre_name;
                                                     };
                                                 ]))
                                   | _ -> [])
                               | None -> []
                             in
                             history_links @ caller_pre_links
                       end))
  in
  invariant_relations @ delay_relations

let of_node_analysis ~(node_name : Ast.ident) ~(nodes : Abs.node list)
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
    |> List.filter (is_feasible_product_step ~analysis)
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
  let generated_clauses =
    build_generated_clauses ~node ~analysis ~initial_state:initial_product_state ~steps:product_steps
  in
  let pre_k_map = build_pre_k_infos (Abs.to_ast_node node) in
  let generated_clauses = List.filter_map (lower_generated_clause ~pre_k_map) generated_clauses in
  let relational_generated_clauses =
    List.concat_map (relationalize_generated_clause ~pre_k_map) generated_clauses
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
  {
    reactive_program;
    assume_automaton;
    guarantee_automaton;
    initial_product_state;
    product_states;
    product_steps;
    product_coverage;
    generated_clauses;
    relational_generated_clauses;
    instance_relations;
    callee_tick_abis;
    call_site_instantiations;
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
        Printf.sprintf "  trans %s -> %s guard=%s" t.src_state t.dst_state (string_of_fo t.guard))
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

let render_product (ir : node_ir) : string list =
  let header =
    Printf.sprintf "explicit_product initial=%s states=%d steps=%d clauses=%d"
      (string_of_product_state ir.initial_product_state) (List.length ir.product_states)
      (List.length ir.product_steps) (List.length ir.generated_clauses)
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
  let clauses =
    List.map
      (fun (clause : generated_clause_ir) ->
        let subject =
          match clause.anchor with
          | ClauseAnchorProductState st -> string_of_product_state st
          | ClauseAnchorProductStep step ->
              Printf.sprintf "%s -> %s" (string_of_product_state step.src)
                (string_of_product_state step.dst)
        in
        let hyps = String.concat ", " (List.map string_of_clause_fact clause.hypotheses) in
        let concls = String.concat ", " (List.map string_of_clause_fact clause.conclusions) in
        Printf.sprintf "  clause %s on %s if [%s] then [%s]" (string_of_clause_origin clause.origin)
          subject hyps concls)
      ir.generated_clauses
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
  header :: (coverage :: (states @ steps @ clauses @ instance_relations))

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
    FRel (HNow (Ast_builders.mk_var lhs), REq, HNow (Ast_builders.mk_var rhs))
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
      generated_clauses = [];
      relational_generated_clauses = [];
      instance_relations = [];
      callee_tick_abis = [ abi ];
      call_site_instantiations = [ inst ];
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
