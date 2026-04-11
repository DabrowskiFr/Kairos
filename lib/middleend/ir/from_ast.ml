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

open Ast
open Fo_specs

module PT = Product_types

let ( let* ) = Result.bind

let rec fo_mentions_current_input ~(is_input : ident -> bool) (f : Fo_formula.t) =
  let rec hexpr_uses_input (h : hexpr) =
    match h.hexpr with
    | HPreK _ | HLitInt _ | HLitBool _ -> false
    | HVar name -> is_input name
    | HUn (_, inner) -> hexpr_uses_input inner
    | HArithBin (_, a, b) | HBoolBin (_, a, b) | HCmp (_, a, b) ->
        hexpr_uses_input a || hexpr_uses_input b
  in
  match f with
  | Fo_formula.FTrue | Fo_formula.FFalse -> false
  | Fo_formula.FAtom (FRel (h1, _, h2)) -> hexpr_uses_input h1 || hexpr_uses_input h2
  | Fo_formula.FAtom (FPred (_, hs)) -> List.exists hexpr_uses_input hs
  | Fo_formula.FNot f -> fo_mentions_current_input ~is_input f
  | Fo_formula.FAnd (a, b) | Fo_formula.FOr (a, b) | Fo_formula.FImp (a, b) ->
      fo_mentions_current_input ~is_input a || fo_mentions_current_input ~is_input b

let convert_state_invariants (node_name : ident) (inputs : vdecl list)
    (invs : Ast.invariant_state_rel list) : Ir.state_invariant list =
  let input_names = List.map (fun (v : vdecl) -> v.vname) inputs in
  let is_input x = List.mem x input_names in
  List.map
    (fun (inv : Ast.invariant_state_rel) ->
      if fo_mentions_current_input ~is_input inv.formula then
        failwith
          (Printf.sprintf
             "State invariant for node %s in state %s mentions a current input, \
              which is forbidden for node-entry invariants: %s"
             node_name inv.state (Logic_pretty.string_of_fo inv.formula));
      { Ir.state = inv.state; formula = inv.formula })
    invs

let rec stmt_contains_call (s : Ast.stmt) : bool =
  match s.stmt with
  | SCall _ -> true
  | SIf (_, then_branch, else_branch) ->
      List.exists stmt_contains_call then_branch || List.exists stmt_contains_call else_branch
  | SMatch (_, branches, default_branch) ->
      List.exists
        (fun (_ctor, body) -> List.exists stmt_contains_call body)
        branches
      || List.exists stmt_contains_call default_branch
  | SAssign _ | SSkip -> false

let transition_contains_call (t : Ast.transition) : bool =
  List.exists stmt_contains_call t.body

let node_uses_calls (n : Ast.node) : bool =
  n.semantics.sem_instances <> [] || List.exists transition_contains_call n.semantics.sem_trans

let of_ast_node (n : Ast.node) : Ir.node_ir =
  let semantics = Ast.semantics_of_node n in
  let spec = Ast.specification_of_node n in
  {
    semantics =
      {
        Ir.sem_nname = semantics.sem_nname;
        sem_inputs = semantics.sem_inputs;
        sem_outputs = semantics.sem_outputs;
        sem_locals = semantics.sem_locals;
        sem_states = semantics.sem_states;
        sem_init_state = semantics.sem_init_state;
      };
    source_info =
      {
        assumes = spec.spec_assumes;
        guarantees = spec.spec_guarantees;
        state_invariants =
          convert_state_invariants semantics.sem_nname semantics.sem_inputs
            spec.spec_invariants_state_rel;
      };
    temporal_layout = [];
    summaries = [];
    init_invariant_goals = [];
  }

let of_ast_program_context (p : Ast.program) : Ir.node_ir list = List.map of_ast_node p

let source_nodes_by_name (source_program : Ast.program) : (Ast.ident * Ast.node) list =
  List.map (fun (node : Ast.node) -> (node.semantics.sem_nname, node)) source_program

let analysis_context_of_source_node (source_node : Ast.node) : Ir.node_ir =
  let semantics = Ast.semantics_of_node source_node in
  {
    Ir.semantics =
      {
        sem_nname = semantics.sem_nname;
        sem_inputs = semantics.sem_inputs;
        sem_outputs = semantics.sem_outputs;
        sem_locals = semantics.sem_locals;
        sem_states = semantics.sem_states;
        sem_init_state = semantics.sem_init_state;
      };
    source_info = { assumes = []; guarantees = []; state_invariants = [] };
    temporal_layout = [];
    summaries = [];
    init_invariant_goals = [];
  }

let build_node_analysis ~(automata : Automata_generation.node_builds) (source_node : Ast.node) :
    (Temporal_automata.node_data, string) result =
  let node = analysis_context_of_source_node source_node in
  let* build =
    match List.assoc_opt node.semantics.sem_nname automata with
    | Some value -> Ok value
    | None ->
        Error
          (Printf.sprintf "Missing automata build for IR node %s" node.semantics.sem_nname)
  in
  Ok
    (Product_build.analyze_node ~build ~node
       ~program_transitions:(Ir_transition.prioritized_program_transitions_of_node source_node))

let build_analyses ~(automata : Automata_generation.node_builds)
    ~(source_nodes : (Ast.ident * Ast.node) list) :
    ((Ast.ident * Temporal_automata.node_data) list, string) result =
  let rec collect acc = function
    | [] -> Ok (List.rev acc)
    | (node_name, source_node) :: rest ->
        let* analysis = build_node_analysis ~automata source_node in
        collect ((node_name, analysis) :: acc) rest
  in
  collect [] source_nodes

let simplify_fo (f : Fo_formula.t) : Fo_formula.t =
  match Fo_z3_solver.simplify_fo_formula f with Some simplified -> simplified | None -> f

let product_state_of_pt (st : PT.product_state) : Ir.product_state =
  {
    prog_state = st.prog_state;
    assume_state_index = st.assume_state;
    guarantee_state_index = st.guarantee_state;
  }

let is_live_product_state ~(analysis : Temporal_automata.node_data) (st : PT.product_state) : bool =
  st.assume_state <> analysis.assume_bad_idx && st.guarantee_state <> analysis.guarantee_bad_idx

let is_relevant_product_step ~(analysis : Temporal_automata.node_data) (step : PT.product_step) : bool =
  is_live_product_state ~analysis step.src
  && (analysis.assume_bad_idx < 0 || step.dst.assume_state <> analysis.assume_bad_idx)

let classify_case ~(analysis : Temporal_automata.node_data) (dst : PT.product_state) : PT.step_class =
  if analysis.assume_bad_idx >= 0 && dst.assume_state = analysis.assume_bad_idx then PT.Bad_assumption
  else if analysis.guarantee_bad_idx >= 0 && dst.guarantee_state = analysis.guarantee_bad_idx then
    PT.Bad_guarantee
  else PT.Safe

let transition_indices (program_transitions : Ir.transition list) : (Ir.transition, int) Hashtbl.t =
  program_transitions
  |> List.mapi (fun idx t -> (t, idx))
  |> List.to_seq |> Hashtbl.of_seq

let program_outgoing (program_transitions : Ir.transition list) : (ident, Ir.transition list) Hashtbl.t =
  let tbl = Hashtbl.create 16 in
  List.iter
    (fun (t : Ir.transition) ->
      let prev = Hashtbl.find_opt tbl t.src_state |> Option.value ~default:[] in
      Hashtbl.replace tbl t.src_state (t :: prev))
    program_transitions;
  tbl

let automaton_outgoing (grouped : Automaton_types.transition list) :
    (int, Automaton_types.transition list) Hashtbl.t =
  let tbl = Hashtbl.create 16 in
  List.iter
    (fun (((src, _guard, _dst) as edge) : Automaton_types.transition) ->
      let prev = Hashtbl.find_opt tbl src |> Option.value ~default:[] in
      Hashtbl.replace tbl src (edge :: prev))
    grouped;
  tbl

let edges_from_outgoing (outgoing : (int, Automaton_types.transition list) Hashtbl.t) idx =
  Hashtbl.find_opt outgoing idx |> Option.value ~default:[]

let build_minimal_summaries ~(analysis : Temporal_automata.node_data)
    ~(program_transitions : Ir.transition list) ~(node : Ir.node_ir) : Ir.product_step_summary list =
  let transition_indices = transition_indices program_transitions in
  let prog_outgoing = program_outgoing program_transitions in
  let assume_outgoing = automaton_outgoing analysis.assume_grouped_edges in
  let guarantee_outgoing = automaton_outgoing analysis.guarantee_grouped_edges in
  let groups = Hashtbl.create 32 in
  let order = ref [] in
  let seen = Hashtbl.create 64 in
  let q = Queue.create () in
  let push_state st =
    if not (Hashtbl.mem seen st) then (
      Hashtbl.add seen st ();
      Queue.add st q)
  in
  let _ = node in
  push_state analysis.exploration.initial_state;
  while not (Queue.is_empty q) do
    let src = Queue.take q in
    let prog_edges = Hashtbl.find_opt prog_outgoing src.prog_state |> Option.value ~default:[] in
    let assume_edges = edges_from_outgoing assume_outgoing src.assume_state in
    let guarantee_edges = edges_from_outgoing guarantee_outgoing src.guarantee_state in
    List.iter
      (fun (prog_transition : Ir.transition) ->
        match Hashtbl.find_opt transition_indices prog_transition with
        | None -> ()
        | Some step_uid ->
            List.iter
              (fun (((_assume_src, assume_guard_raw, assume_dst) as assume_edge) :
                    Automaton_types.transition) ->
                List.iter
                  (fun (((_guarantee_src, guarantee_guard_raw, guarantee_dst) as guarantee_edge) :
                        Automaton_types.transition) ->
                    let dst =
                      {
                        PT.prog_state = prog_transition.dst_state;
                        assume_state = assume_dst;
                        guarantee_state = guarantee_dst;
                      }
                    in
                    push_state dst;
                    let step_class = classify_case ~analysis dst in
                    let step =
                      {
                        PT.src;
                        dst;
                        prog_transition;
                        prog_guard =
                          (match prog_transition.guard_iexpr with
                          | None -> Fo_formula.FTrue
                          | Some g -> Fo_specs.iexpr_to_fo_with_atoms [] g |> simplify_fo);
                        assume_edge;
                        assume_guard = simplify_fo assume_guard_raw;
                        guarantee_edge;
                        guarantee_guard = simplify_fo guarantee_guard_raw;
                        step_class;
                      }
                    in
                    if is_relevant_product_step ~analysis step then (
                      let key = (step_uid, step.src, step.assume_edge) in
                      if not (Hashtbl.mem groups key) then order := key :: !order;
                      let previous = Hashtbl.find_opt groups key |> Option.value ~default:[] in
                      Hashtbl.replace groups key ((step, step_uid) :: previous)))
                  guarantee_edges)
              assume_edges)
      prog_edges
  done;
  List.rev !order
  |> List.filter_map (fun key ->
         match Hashtbl.find_opt groups key with
         | None -> None
         | Some grouped ->
             let grouped = List.rev grouped in
             let ((repr_step : PT.product_step), step_uid) = List.hd grouped in
             let safe_cases =
               grouped
               |> List.filter_map (fun ((step : PT.product_step), _) ->
                      match step.step_class with
                      | PT.Safe ->
                          Some
                            ({
                               product_dst = product_state_of_pt step.dst;
                               admissible_guard =
                                 Ir_formula.with_origin Formula_origin.GuaranteeAutomaton
                                   step.guarantee_guard;
                             } : Ir.safe_product_case)
                      | PT.Bad_assumption | PT.Bad_guarantee -> None)
             in
             let unsafe_cases =
               grouped
               |> List.filter_map (fun ((step : PT.product_step), _) ->
                      match step.step_class with
                      | PT.Bad_guarantee ->
                          Some
                            ({
                               product_dst = product_state_of_pt step.dst;
                               excluded_guard =
                                 Ir_formula.with_origin Formula_origin.GuaranteeViolation
                                   step.guarantee_guard;
                             } : Ir.unsafe_product_case)
                      | PT.Safe | PT.Bad_assumption -> None)
             in
             Some
               ({
                  trace = { step_uid };
                  identity =
                    {
                      program_step =
                        {
                          src_state = repr_step.prog_transition.src_state;
                          dst_state = repr_step.prog_transition.dst_state;
                          guard_iexpr = repr_step.prog_transition.guard_iexpr;
                          body_stmts = repr_step.prog_transition.body_stmts;
                        };
                      product_src = product_state_of_pt repr_step.src;
                      assume_guard = repr_step.assume_guard;
                    };
                  requires = [];
                  ensures = [];
                  safe_cases;
                  unsafe_cases;
                }
                 : Ir.product_step_summary))

let with_minimal_summaries ~(analyses : (Ast.ident * Temporal_automata.node_data) list)
    ~(source_nodes : (Ast.ident * Ast.node) list)
    (nodes : Ir.node_ir list) : (Ir.node_ir list, string) result =
  let rec collect acc = function
    | [] -> Ok (List.rev acc)
    | (node : Ir.node_ir) :: rest ->
        let node_name = node.semantics.sem_nname in
        let* analysis =
          match List.assoc_opt node_name analyses with
          | Some value -> Ok value
          | None ->
              Error (Printf.sprintf "Missing product analysis for normalized node %s" node_name)
        in
        let* program_transitions =
          match List.assoc_opt node_name source_nodes with
          | None -> Error (Printf.sprintf "Missing source AST node for normalized node %s" node_name)
          | Some source_node -> Ok (Ir_transition.prioritized_program_transitions_of_node source_node)
        in
        let summaries = build_minimal_summaries ~analysis ~program_transitions ~node in
        collect ({ node with summaries } :: acc) rest
  in
  collect [] nodes

let of_ast_program ~(automata : Automata_generation.node_builds) (program : Ast.program) :
    (Ir.node_ir list, string) result =
  match List.find_opt node_uses_calls program with
  | Some node ->
      Error
        (Printf.sprintf
           "Calls are not supported in this Kairos version (node '%s')."
           node.semantics.sem_nname)
  | None ->
      let source_nodes = source_nodes_by_name program in
      let* analyses = build_analyses ~automata ~source_nodes in
      of_ast_program_context program
      |> with_minimal_summaries ~analyses ~source_nodes
