(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *---------------------------------------------------------------------------*)
open Core_syntax
open Ast
open Temporal_support
open Pretty
open Pre_k_layout
open Core_syntax_builders

module Abs = Ir
module PT = Product_types

type node_input = {
  node_name : ident;
  source_node : Ast.node;
  node : Ir.node_ir;
  analysis : Temporal_automata.node_data;
}

type node_output = {
  normalized_ir : Proof_kernel_types.node_ir;
  exported_summary : Proof_kernel_types.exported_node_summary_ir;
}

let simplify_fo (f : Core_syntax.hexpr) : Core_syntax.hexpr =
  match Fo_z3_solver.simplify_fo_formula f with Some simplified -> simplified | None -> f

let fo_of_expr (e : expr) : Core_syntax.hexpr = hexpr_of_expr e

let extract_delay_spec (guarantees : ltl list) : (ident * ident) option =
  let rec find_in_ltl = function
    | LG a -> find_in_ltl a
    | LX a -> find_in_ltl a
    | LAtom (lhs, REq, rhs) -> (
        match (lhs.hexpr, rhs.hexpr) with
        | HVar out, HPreK (b, 1) -> Some (out, b)
        | HPreK (b, 1), HVar out -> Some (out, b)
        | _ -> None)
    | _ -> None
  in
  List.find_map find_in_ltl guarantees

let program_transitions_of_ast_node (node : Ast.node) : Ir.transition list =
  Ir_transition.prioritized_program_transitions_of_node node

let automaton_guard_fo ~(atom_map_exprs : (ident * expr) list) (g : Automaton_types.guard) : Core_syntax.hexpr =
  let _ = atom_map_exprs in
  simplify_fo g

type lit = { var : ident; cst : string; is_pos : bool }

let lit_of_rel (h1 : hexpr) (r : relop) (h2 : hexpr) : lit option =
  let mk ?(is_pos = true) v c = Some { var = v; cst = c; is_pos } in
  let var_of_hexpr (h : hexpr) = match h.hexpr with HVar v -> Some v | _ -> None in
  let const_of_hexpr (h : hexpr) =
    match h.hexpr with
    | HLitInt i -> Some (string_of_int i)
    | HLitBool b -> Some (if b then "true" else "false")
    | _ -> None
  in
  let fallback_var (h : hexpr) = Pretty.string_of_hexpr h in
  let build ~is_pos h_left h_right =
    match (var_of_hexpr h_left, const_of_hexpr h_right) with
    | Some v, Some c -> mk ~is_pos v c
    | _ -> (
        match (const_of_hexpr h_left, var_of_hexpr h_right) with
        | Some c, Some v -> mk ~is_pos v c
        | _ -> (
            match (const_of_hexpr h_left, const_of_hexpr h_right) with
            | Some c, _ -> mk ~is_pos (fallback_var h_right) c
            | _, Some c -> mk ~is_pos (fallback_var h_left) c
            | _ -> None))
  in
  match r with REq -> build ~is_pos:true h1 h2 | RNeq -> build ~is_pos:false h1 h2 | _ -> None

let rec conj_lits (f : Core_syntax.hexpr) : lit list option =
  match f.hexpr with
  | HLitBool true -> Some []
  | HCmp (r, h1, h2) -> Option.map (fun l -> [ l ]) (lit_of_rel h1 r h2)
  | HUn (Not, { hexpr = HCmp (REq, h1, h2); _ }) ->
      Option.map (fun l -> [ { l with is_pos = false } ]) (lit_of_rel h1 REq h2)
  | HBin (And, a, b) -> begin
      match (conj_lits a, conj_lits b) with
      | Some la, Some lb -> Some (la @ lb)
      | _ -> None
    end
  | _ -> None

let disj_conjs (f : Core_syntax.hexpr) : lit list list option =
  let rec go = function
    | { hexpr = HBin (Or, a, b); _ } -> go a @ go b
    | x -> [ x ]
  in
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

let fo_overlap_conservative (a : Core_syntax.hexpr) (b : Core_syntax.hexpr) : bool =
  match (disj_conjs a, disj_conjs b) with
  | Some da, Some db ->
      List.exists (fun ca -> List.exists (fun cb -> lits_consistent ca cb) db) da
  | _ -> true

let guards_may_overlap (a : Core_syntax.hexpr) (b : Core_syntax.hexpr) : bool =
  match simplify_fo (Core_syntax_builders.mk_hand a b) with
  | { hexpr = HLitBool false; _ } -> false
  | _ -> fo_overlap_conservative a b

let product_state_of_pt (st : PT.product_state) : Proof_kernel_types.product_state_ir =
  {
    prog_state = st.prog_state;
    assume_state_index = st.assume_state;
    guarantee_state_index = st.guarantee_state;
  }

let product_step_kind_of_pt = function
  | PT.Safe -> Proof_kernel_types.StepSafe
  | PT.Bad_assumption -> Proof_kernel_types.StepBadAssumption
  | PT.Bad_guarantee -> Proof_kernel_types.StepBadGuarantee

let is_live_state ~(analysis : Temporal_automata.node_data) (st : PT.product_state) : bool =
  st.assume_state <> analysis.assume_bad_idx && st.guarantee_state <> analysis.guarantee_bad_idx

let temporal_locals_of_layout ~(existing_locals : vdecl list) (layout : Ir.temporal_layout) :
    vdecl list =
  let existing = List.map (fun (v : vdecl) -> v.vname) existing_locals in
  layout
  |> List.fold_left
       (fun acc info ->
         if List.exists
              (fun (existing_info : Temporal_support.pre_k_info) ->
                existing_info.Temporal_support.var_name = info.Temporal_support.var_name
                && existing_info.Temporal_support.names = info.Temporal_support.names)
              acc
         then acc
         else acc @ [ info ])
       []
  |> List.concat_map (fun info ->
         List.filter_map
           (fun name ->
             if List.mem name existing then None else Some { vname = name; vty = info.vty })
           info.names)

let build_reactive_program ~(node_name : ident) ~(source_node : Ast.node) :
    Proof_kernel_types.reactive_program_ir =
  Proof_kernel_product.build_reactive_program ~node_name
    ~source_node
    ~program_transitions:(program_transitions_of_ast_node source_node)

let build_automaton ~(role : Proof_kernel_types.automaton_role) ~(labels : string list) ~(bad_idx : int)
    ~(grouped_edges : PT.automaton_edge list) ~(atom_map_exprs : (ident * expr) list) :
    Proof_kernel_types.safety_automaton_ir =
  Proof_kernel_product.build_automaton ~role ~labels ~bad_idx ~grouped_edges ~atom_map_exprs
    ~automaton_guard_fo:(fun atom_map_exprs guard_raw ->
      automaton_guard_fo ~atom_map_exprs guard_raw)

let build_product_step ~(reactive_program : Proof_kernel_types.reactive_program_ir) (step : PT.product_step) :
    Proof_kernel_types.product_step_ir =
  Proof_kernel_product.build_product_step ~reactive_program step

let is_feasible_product_step ~(node : Abs.node_ir) ~(analysis : Temporal_automata.node_data)
    (step : Proof_kernel_types.product_step_ir) : bool =
  Proof_kernel_product.is_feasible_product_step ~node ~analysis step

let synthesize_fallback_product_steps ~(node : Abs.node_ir) ~(analysis : Temporal_automata.node_data)
    ~(source_node : Ast.node) ~(reactive_program : Proof_kernel_types.reactive_program_ir)
    ~(live_states : PT.product_state list) :
    Proof_kernel_types.product_step_ir list =
  Proof_kernel_product.synthesize_fallback_product_steps
    ~program_transitions:(program_transitions_of_ast_node source_node)
    ~node ~analysis ~reactive_program
    ~live_states
    ~automaton_guard_fo:(fun atom_map_exprs guard_raw ->
      automaton_guard_fo ~atom_map_exprs guard_raw)
    ~product_state_of_pt ~product_step_kind_of_pt ~is_live_state

let build_generated_clauses ~(node : Abs.node_ir) ~(analysis : Temporal_automata.node_data)
    ~(initial_state : Proof_kernel_types.product_state_ir) ~(steps : Proof_kernel_types.product_step_ir list) :
    Proof_kernel_types.generated_clause_ir list =
  Proof_kernel_generated_clauses.build_generated_clauses ~node ~analysis ~initial_state ~steps
    ~automaton_guard_fo:(fun atom_map_exprs guard_raw ->
      automaton_guard_fo ~atom_map_exprs guard_raw)
    ~is_live_state

let node_signature_of_ast ~(temporal_layout : Ir.temporal_layout) (n : Ast.node) :
    Proof_kernel_types.node_signature_ir =
  let sem = n.semantics in
  let temporal_locals = temporal_locals_of_layout ~existing_locals:sem.sem_locals temporal_layout in
  {
    node_name = sem.sem_nname;
    inputs = sem.sem_inputs;
    outputs = sem.sem_outputs;
    locals = sem.sem_locals @ temporal_locals;
    states = sem.sem_states;
    init_state = sem.sem_init_state;
  }

let build_exported_summary ~(input : node_input)
    ~(normalized_ir : Proof_kernel_types.node_ir) :
    Proof_kernel_types.exported_node_summary_ir =
  let source_node = input.source_node in
  let node = input.node in
  {
    signature = node_signature_of_ast ~temporal_layout:node.temporal_layout source_node;
    normalized_ir;
    coherency_goals = node.init_invariant_goals;
    temporal_layout = node.temporal_layout;
    delay_spec = extract_delay_spec node.source_info.guarantees;
    assumes = node.source_info.assumes;
    guarantees = node.source_info.guarantees;
  }

let build_normalized_ir (input : node_input) : Proof_kernel_types.node_ir =
  let node_name = input.node_name in
  let source_node = input.source_node in
  let node = input.node in
  let analysis = input.analysis in
  let reactive_program = build_reactive_program ~node_name ~source_node in
  let assume_automaton =
    build_automaton ~role:Proof_kernel_types.Assume ~labels:analysis.assume_state_labels
      ~bad_idx:analysis.assume_bad_idx ~grouped_edges:analysis.assume_grouped_edges
      ~atom_map_exprs:analysis.assume_atom_map_exprs
  in
  let guarantee_automaton =
    build_automaton ~role:Proof_kernel_types.Guarantee ~labels:analysis.guarantee_state_labels
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
      synthesize_fallback_product_steps ~node ~analysis ~source_node ~reactive_program
        ~live_states:live_product_states
  in
  let product_coverage =
    if explicit_steps <> [] then Proof_kernel_types.CoverageExplicit
    else if product_steps <> [] then Proof_kernel_types.CoverageFallback
    else Proof_kernel_types.CoverageEmpty
  in
  let historical_generated_clauses =
    build_generated_clauses ~node ~analysis ~initial_state:initial_product_state ~steps:product_steps
  in
  let temporal_bindings = Ir_formula.temporal_bindings_of_node node in
  let eliminated_generated_clauses =
    List.filter_map (Proof_kernel_clause_lowering.lower_generated_clause ~temporal_bindings)
      historical_generated_clauses
  in
  let symbolic_generated_clauses =
    List.concat_map (Proof_kernel_clause_lowering.relationalize_generated_clause ~temporal_bindings)
      eliminated_generated_clauses
  in
  let proof_step_summaries =
    Proof_kernel_step_summaries.build_proof_step_summaries ~node ~reactive_program ~product_steps
      ~temporal_layout:node.temporal_layout
      ~initial_product_state ~symbolic_generated_clauses
  in
  let ghost_locals =
    temporal_locals_of_layout ~existing_locals:source_node.semantics.sem_locals node.temporal_layout
  in
  {
    Proof_kernel_types.reactive_program;
    assume_automaton;
    guarantee_automaton;
    initial_product_state;
    product_states;
    product_steps;
    product_coverage;
    temporal_layout = node.temporal_layout;
    historical_generated_clauses;
    eliminated_generated_clauses;
    symbolic_generated_clauses;
    proof_step_summaries;
    ghost_locals;
  }

let compile_node (input : node_input) : node_output =
  let normalized_ir = build_normalized_ir input in
  let exported_summary = build_exported_summary ~input ~normalized_ir in
  { normalized_ir; exported_summary }
