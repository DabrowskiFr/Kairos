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
open Automaton_types

module PT = Product_types
module Vm = Verification_model

let ( let* ) = Result.bind

let convert_state_invariants (node_name : ident) (inputs : vdecl list)
    (invs : Vm.state_invariant list) : Ir.state_invariant list =
  let input_names = Fo_current_input.input_names inputs in
  List.map
    (fun (inv : Vm.state_invariant) ->
      let formula =
        Fo_current_input.require_no_current_input
          ~context:
            (Printf.sprintf
               "State invariant for node %s in state %s" node_name inv.state)
          ~input_names inv.formula
      in
      { Ir.state = inv.state; formula })
    invs

let of_model_node (n : Vm.node_model) : Core_syntax.historical Ir.node_ir =
  {
    semantics =
      {
        Ir.sem_nname = n.node_name;
        sem_type_decls = n.type_decls;
        sem_function_decls = n.function_decls;
        sem_inputs = n.inputs;
        sem_outputs = n.outputs;
        sem_locals = n.locals @ n.ghosts;
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

let transition_of_program_step
    (step : Vm.program_step) : Ir.transition =
  {
    src_state = step.src_state;
    dst_state = step.dst_state;
    guard_expr = step.guard_expr;
    body_stmts = step.body_stmts;
  }

let validate_node_origin ~(model : Vm.node_model)
    (node : 'phase Ir.node_ir) : (unit, string) result =
  let expected = of_model_node model in
  if node.semantics <> expected.semantics then
    Error
      (Printf.sprintf
         "IR node '%s' does not have the signature of proof case '%s'"
         node.semantics.sem_nname model.node_name)
  else if node.source_info <> expected.source_info then
    Error
      (Printf.sprintf
         "IR node '%s' does not have the source contract of proof case '%s'"
         node.semantics.sem_nname model.node_name)
  else
    let steps = Array.of_list model.steps in
    let validate_summary
        (summary : 'phase Ir.product_step_summary) =
      let step_uid = summary.trace.step_uid in
      if step_uid < 0 || step_uid >= Array.length steps then
        Error
          (Printf.sprintf
             "IR node '%s' refers to transition index %d outside proof case \
              '%s'"
             node.semantics.sem_nname step_uid model.node_name)
      else
        let expected_transition =
          transition_of_program_step steps.(step_uid)
        in
        if summary.identity.program_step <> expected_transition then
          Error
            (Printf.sprintf
               "IR node '%s' transition %d does not originate from proof case \
                '%s'"
               node.semantics.sem_nname step_uid model.node_name)
        else if
          not
            (String.equal summary.identity.product_src.prog_state
               expected_transition.src_state)
        then
          Error
            (Printf.sprintf
               "IR node '%s' transition %d has an inconsistent product source"
               node.semantics.sem_nname step_uid)
        else
          let destinations =
            List.map
              (fun (case : 'phase Ir.safe_product_case) ->
                case.product_dst)
              summary.safe_cases
            @ List.map
                (fun (case : 'phase Ir.unsafe_product_case) ->
                  case.product_dst)
                summary.unsafe_cases
          in
          if
            List.for_all
              (fun (destination : Ir.product_state) ->
                String.equal destination.prog_state
                  expected_transition.dst_state)
              destinations
          then Ok ()
          else
            Error
              (Printf.sprintf
                 "IR node '%s' transition %d has an inconsistent product \
                  destination"
                 node.semantics.sem_nname step_uid)
    in
    let rec validate_summaries = function
      | [] -> Ok ()
      | summary :: rest ->
          let* () = validate_summary summary in
          validate_summaries rest
    in
    validate_summaries node.summaries

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
  Ok
    (Product_build.analyze_node ~build ~node
       ~program_transitions:node.steps)

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

let transition_indices (program_transitions : Vm.program_step list) :
    (Vm.program_step, int) Hashtbl.t =
  program_transitions
  |> List.mapi (fun idx t -> (t, idx))
  |> List.to_seq |> Hashtbl.of_seq

let build_minimal_summaries ~(analysis : Temporal_automata.node_data)
    ~(program_transitions : Vm.program_step list) :
    Core_syntax.historical Ir.product_step_summary list =
  let transition_indices = transition_indices program_transitions in
  let groups = Hashtbl.create 32 in
  let order = ref [] in
  analysis.exploration.steps
  |> List.iter (fun (step : PT.product_step) ->
         match Hashtbl.find_opt transition_indices step.prog_transition with
         | None -> ()
         | Some step_uid ->
             if is_relevant_product_step ~analysis step then (
               let key = (step_uid, step.src, step.assume_edge) in
               if not (Hashtbl.mem groups key) then order := key :: !order;
               let previous =
                 Hashtbl.find_opt groups key |> Option.value ~default:[]
               in
               Hashtbl.replace groups key ((step, step_uid) :: previous)));
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
                             } : Core_syntax.historical Ir.safe_product_case)
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
                             } : Core_syntax.historical Ir.unsafe_product_case)
                      | PT.Safe | PT.Bad_assumption -> None)
             in
             Some
               ({
                  trace = { step_uid };
                  identity =
                    {
                      program_step =
                        transition_of_program_step
                          repr_step.prog_transition;
                      product_src = product_state_of_pt repr_step.src;
                      assume_guard = repr_step.assume_guard;
                    };
                  propagation_requires = [];
                  requires = [];
                  ensures = [];
                  elaboration_checks =
                    List.map Ir_formula.make
                      repr_step.prog_transition.elaboration_checks;
                  safe_cases;
                  unsafe_cases;
                }
                 : Core_syntax.historical Ir.product_step_summary))

type analyzed_node = {
  model : Vm.node_model;
  analysis : Temporal_automata.node_data;
  ir : Core_syntax.historical Ir.node_ir;
}

let analyze_model_program
    ~(automata : (Core_syntax.ident * automata_spec) list)
    (program : Vm.program_model) :
    (analyzed_node list, string) result =
  let rec collect acc = function
    | [] -> Ok (List.rev acc)
    | (model : Vm.node_model) :: rest ->
        let* analysis = build_node_analysis ~automata model in
        let ir = of_model_node model in
        let summaries =
          build_minimal_summaries ~analysis
            ~program_transitions:model.steps
        in
        let ir = { ir with summaries } in
        collect ({ model; analysis; ir } :: acc) rest
  in
  collect [] program
