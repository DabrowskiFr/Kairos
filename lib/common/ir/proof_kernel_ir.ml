open Ast
open Support
open Fo_specs
open Collect

module Abs = Normalized_program
module PT = Product_types

include Proof_kernel_types

let phase_state_case_name = Proof_kernel_naming.phase_state_case_name
let phase_step_pre_case_name = Proof_kernel_naming.phase_step_pre_case_name
let phase_step_post_case_name = Proof_kernel_naming.phase_step_post_case_name

let fo_of_iexpr (e : iexpr) : ltl = iexpr_to_fo_with_atoms [] e

let automaton_guard_fo ~(atom_map_exprs : (ident * iexpr) list) (g : Spot_automaton.guard) : ltl =
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

let has_effective_product_coverage (ir : node_ir) : bool = ir.product_coverage <> CoverageEmpty

let pre_k_locals_of_ast (n : Ast.node) : Ast.vdecl list =
  let existing = List.map (fun (v : Ast.vdecl) -> v.vname) n.semantics.sem_locals in
  build_pre_k_infos n
  |> List.fold_left
       (fun acc (_, info) ->
         if List.exists
              (fun (existing_info : Temporal_support.pre_k_info) ->
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

let callee_tick_abi_of_node = Proof_kernel_calls.callee_tick_abi_of_node
let build_reactive_program ~(node_name : Ast.ident) ~(node : Abs.node) : reactive_program_ir =
  Proof_kernel_program.build_reactive_program ~node_name ~node

let build_automaton ~(role : automaton_role) ~(labels : string list) ~(bad_idx : int)
    ~(grouped_edges : PT.automaton_edge list) ~(atom_map_exprs : (Ast.ident * Ast.iexpr) list) :
    safety_automaton_ir =
  Proof_kernel_program.build_automaton ~role ~labels ~bad_idx ~grouped_edges ~atom_map_exprs
    ~automaton_guard_fo:(fun atom_map_exprs guard_raw ->
      automaton_guard_fo ~atom_map_exprs guard_raw)

let build_product_step ~(reactive_program : reactive_program_ir) (step : PT.product_step) : product_step_ir =
  Proof_kernel_program.build_product_step ~reactive_program step

let is_feasible_product_step ~(node : Abs.node) ~(analysis : Product_build.analysis)
    (step : product_step_ir) : bool =
  Proof_kernel_program.is_feasible_product_step ~node ~analysis step

let synthesize_fallback_product_steps ~(node : Abs.node) ~(analysis : Product_build.analysis)
    ~(reactive_program : reactive_program_ir) ~(live_states : PT.product_state list) :
    product_step_ir list =
  Proof_kernel_program.synthesize_fallback_product_steps ~node ~analysis ~reactive_program
    ~live_states
    ~automaton_guard_fo:(fun atom_map_exprs guard_raw ->
      automaton_guard_fo ~atom_map_exprs guard_raw)
    ~product_state_of_pt ~product_step_kind_of_pt ~is_live_state

let build_generated_clauses ~(node : Abs.node) ~(analysis : Product_build.analysis)
    ~(initial_state : product_state_ir) ~(steps : product_step_ir list) : generated_clause_ir list =
  Proof_kernel_clauses.build_generated_clauses ~node ~analysis ~initial_state ~steps
    ~automaton_guard_fo:(fun atom_map_exprs guard_raw ->
      automaton_guard_fo ~atom_map_exprs guard_raw)
    ~is_live_state

let lower_clause_fact = Proof_kernel_clauses.lower_clause_fact
let lower_generated_clause = Proof_kernel_clauses.lower_generated_clause
let relationalize_clause_fact = Proof_kernel_clauses.relationalize_clause_fact
let expand_relational_hypotheses = Proof_kernel_clauses.expand_relational_hypotheses
let normalize_relational_hypotheses = Proof_kernel_clauses.normalize_relational_hypotheses
let relationalize_generated_clause = Proof_kernel_clauses.relationalize_generated_clause

let export_node_summary ~(node : Abs.node) ~(normalized_ir : node_ir) : exported_node_summary_ir =
  let node_ast = Abs.to_ast_node node in
  let pre_k_map = build_pre_k_infos node_ast in
  {
    signature = node_signature_of_ast node_ast;
    normalized_ir;
    tick_summary =
      Proof_kernel_calls.lower_callee_tick_abi ~pre_k_map ~lower_clause_fact
        (callee_tick_abi_of_node ~node);
    user_invariants = node.user_invariants;
    state_invariants = node.specification.spec_invariants_state_rel;
    coherency_goals = node.coherency_goals;
    pre_k_map;
    delay_spec = extract_delay_spec node.specification.spec_guarantees;
    assumes = node.specification.spec_assumes;
    guarantees = node.specification.spec_guarantees;
  }

let rec of_node_analysis ~(node_name : Ast.ident) ~(nodes : Abs.node list)
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
    List.map (build_product_step ~reactive_program) analysis.exploration.steps
    |> List.filter (is_feasible_product_step ~node ~analysis)
  in
  let product_steps =
    if explicit_steps <> [] then explicit_steps
    else
      synthesize_fallback_product_steps ~node ~analysis ~reactive_program
        ~live_states:live_product_states
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
  let proof_step_contracts =
    Proof_kernel_step_contracts.build_proof_step_contracts ~product_steps ~pre_k_map
      ~initial_product_state ~symbolic_generated_clauses
  in
  let instance_relations =
    Proof_kernel_calls.build_instance_relations ~nodes ~external_summaries ~node
      ~node_signature_of_ast ~build_pre_k_infos ~extract_delay_spec ~of_node_analysis
  in
  let called_callee_names =
    Proof_kernel_calls.build_call_site_instantiations ~nodes ~external_summaries ~node
      ~node_signature_of_ast ~build_pre_k_infos ~extract_delay_spec ~of_node_analysis
    |> List.map (fun inst -> inst.callee_node_name)
    |> List.sort_uniq String.compare
  in
  let callee_tick_abis =
    List.filter_map
      (fun callee_name ->
        let local_node =
          List.find_opt (fun (nd : Abs.node) -> nd.semantics.sem_nname = callee_name) nodes
        in
        match local_node with
        | Some callee_node ->
            let callee_ast = Abs.to_ast_node callee_node in
            let callee_pre_k_map = build_pre_k_infos callee_ast in
            Some
              (Proof_kernel_calls.lower_callee_tick_abi ~pre_k_map:callee_pre_k_map
                 ~lower_clause_fact
                 (Proof_kernel_calls.callee_tick_abi_of_node ~node:callee_node))
        | None -> (
            match List.find_opt (fun summary -> summary.signature.node_name = callee_name) external_summaries with
            | Some summary -> Some summary.tick_summary
            | None -> None))
      called_callee_names
  in
  let call_site_instantiations =
    Proof_kernel_calls.build_call_site_instantiations ~nodes ~external_summaries ~node
      ~node_signature_of_ast ~build_pre_k_infos ~extract_delay_spec ~of_node_analysis
  in
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
    proof_step_contracts;
    instance_relations;
    callee_tick_abis;
    call_site_instantiations;
    ghost_locals;
  }
