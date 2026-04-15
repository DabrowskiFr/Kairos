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
open Core_syntax_builders
open Automaton_types

module PT = Product_types
module Vm = Verification_model

let ( let* ) = Result.bind

let fo_mentions_current_input ~(is_input : ident -> bool) (f : Core_syntax.hexpr) =
  let rec go (h : hexpr) =
    match h.hexpr with
    | HLitInt _ | HLitBool _ | HPreK _ -> false
    | HVar name -> is_input name
    | HPred (_, args) -> List.exists go args
    | HUn (_, inner) -> go inner
    | HBin (_, a, b) | HCmp (_, a, b) -> go a || go b
  in
  go f

let convert_state_invariants (node_name : ident) (inputs : vdecl list)
    (invs : Vm.state_invariant list) : Ir.state_invariant list =
  let input_names = List.map (fun (v : vdecl) -> v.vname) inputs in
  let is_input x = List.mem x input_names in
  List.map
    (fun (inv : Vm.state_invariant) ->
      if fo_mentions_current_input ~is_input inv.formula then
        failwith
          (Printf.sprintf
             "State invariant for node %s in state %s mentions a current input, \
              which is forbidden for node-entry invariants: %s"
             node_name inv.state (Pretty.string_of_fo inv.formula));
      { Ir.state = inv.state; formula = inv.formula })
    invs

let of_model_node (n : Vm.node_model) : Ir.node_ir =
  {
    semantics =
      {
        Ir.sem_nname = n.node_name;
        sem_inputs = n.inputs;
        sem_outputs = n.outputs;
        sem_locals = n.locals;
        sem_states = n.states;
        sem_init_state = n.init_state;
      };
    source_info =
      {
        assumes = n.assumes;
        guarantees = n.guarantees;
        state_invariants = convert_state_invariants n.node_name n.inputs n.state_invariants;
      };
    temporal_layout = [];
    summaries = [];
    init_invariant_goals = [];
  }

let of_model_program_context (p : Vm.program_model) : Ir.node_ir list = List.map of_model_node p

let source_nodes_by_name (source_program : Vm.program_model) : (ident * Vm.node_model) list =
  List.map (fun (node : Vm.node_model) -> (node.node_name, node)) source_program

let analysis_context_of_source_node (source_node : Vm.node_model) : Vm.node_model =
  {
    source_node with
    assumes = [];
    guarantees = [];
    state_invariants = [];
  }

let build_node_analysis
    ~(automata : (Core_syntax.ident * automata_spec) list)
    (source_node : Vm.node_model) :
    (Temporal_automata.node_data, string) result =
  let node = analysis_context_of_source_node source_node in
  let* build =
    match List.assoc_opt node.node_name automata with
    | Some value -> Ok value
    | None ->
        Error
          (Printf.sprintf "Missing automata build for IR node %s" node.node_name)
  in
  Ok (Product_build.analyze_node ~build ~node ~program_transitions:node.steps)

let build_analyses
    ~(automata : (Core_syntax.ident * automata_spec) list)
    ~(source_nodes : (ident * Vm.node_model) list) :
    ((ident * Temporal_automata.node_data) list, string) result =
  let rec collect acc = function
    | [] -> Ok (List.rev acc)
    | (node_name, source_node) :: rest ->
        let* analysis = build_node_analysis ~automata source_node in
        collect ((node_name, analysis) :: acc) rest
  in
  collect [] source_nodes

let simplify_fo (f : Core_syntax.hexpr) : Core_syntax.hexpr = f

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

let transition_indices (program_transitions : Vm.program_step list) :
    (Vm.program_step, int) Hashtbl.t =
  program_transitions
  |> List.mapi (fun idx t -> (t, idx))
  |> List.to_seq |> Hashtbl.of_seq

let program_outgoing (program_transitions : Vm.program_step list) :
    (ident, Vm.program_step list) Hashtbl.t =
  let tbl = Hashtbl.create 16 in
  List.iter
    (fun (t : Vm.program_step) ->
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
    ~(program_transitions : Vm.program_step list) ~(node : Ir.node_ir) :
    Ir.product_step_summary list =
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
      (fun (prog_transition : Vm.program_step) ->
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
                          (match prog_transition.guard_expr with
                          | None -> mk_hbool true
                          | Some g -> hexpr_of_expr g |> simplify_fo);
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
                               admissible_guard = Ir_formula.make step.guarantee_guard;
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
                               excluded_guard = Ir_formula.make step.guarantee_guard;
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
                          guard_expr = repr_step.prog_transition.guard_expr;
                          body_stmts = repr_step.prog_transition.body_stmts;
                        };
                      product_src = product_state_of_pt repr_step.src;
                      assume_guard = repr_step.assume_guard;
                    };
                  propagation_requires = [];
                  requires = [];
                  ensures = [];
                  safe_cases;
                  unsafe_cases;
                }
                 : Ir.product_step_summary))

let with_minimal_summaries ~(analyses : (ident * Temporal_automata.node_data) list)
    ~(source_nodes : (ident * Vm.node_model) list)
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
          | None ->
              Error (Printf.sprintf "Missing source model node for normalized node %s" node_name)
          | Some source_node -> Ok source_node.steps
        in
        let summaries = build_minimal_summaries ~analysis ~program_transitions ~node in
        collect ({ node with summaries } :: acc) rest
  in
  collect [] nodes

let of_model_program
    ~(automata : (Core_syntax.ident * automata_spec) list)
    (program : Vm.program_model) :
    (Ir.node_ir list, string) result =
  let source_nodes = source_nodes_by_name program in
  let* analyses = build_analyses ~automata ~source_nodes in
  of_model_program_context program
  |> with_minimal_summaries ~analyses ~source_nodes

