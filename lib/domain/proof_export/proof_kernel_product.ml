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
open Pretty
open Core_syntax_builders

module Abs = Ir
module PT = Product_types
open Proof_kernel_types

let simplify_fo (f : Core_syntax.hexpr) : Core_syntax.hexpr =
  Core_fo_simplifier.simplify f

let fo_of_expr (e : expr) : Core_syntax.hexpr = hexpr_of_expr e

let build_reactive_program ~(node_name : ident) ~(source_node : Verification_model.node_model)
    ~(program_transitions : Abs.transition list) : reactive_program_ir =
  let transitions =
    List.mapi
      (fun idx (t : Abs.transition) ->
        {
          transition_id = Printf.sprintf "tr_%d" idx;
          src_state = t.src_state;
          dst_state = t.dst_state;
          guard =
            (match t.guard_expr with
            | None -> mk_hbool true
            | Some g -> fo_of_expr g |> simplify_fo);
          guard_expr = t.guard_expr;
          requires = [];
          ensures = [];
          body_stmts = t.body_stmts;
        })
      program_transitions
  in
  {
    node_name;
    init_state = source_node.init_state;
    states = source_node.states;
    transitions;
  }

let build_automaton ~(role : automaton_role) ~(labels : string list) ~(bad_idx : int)
    ~(grouped_edges : PT.automaton_edge list) ~automaton_guard_fo : safety_automaton_ir =
  let edges =
    List.map
      (fun ((src, guard_raw, dst) : PT.automaton_edge) ->
        {
          src_index = src;
          dst_index = dst;
          guard = automaton_guard_fo guard_raw;
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

let program_transition_id_of_step ~(reactive_program : reactive_program_ir) (step : PT.product_step) :
    string =
  let matches (tr : reactive_transition_ir) =
    String.equal tr.src_state step.prog_transition.src_state
    && String.equal tr.dst_state step.prog_transition.dst_state
    && simplify_fo tr.guard = simplify_fo step.prog_guard
  in
  match List.find_opt matches reactive_program.transitions with
  | Some tr -> tr.transition_id
  | None ->
      failwith
        (Printf.sprintf
           "Unable to associate product step %s->%s with a reactive transition in node %s"
           step.prog_transition.src_state step.prog_transition.dst_state reactive_program.node_name)

let build_product_step ~(reactive_program : reactive_program_ir) (step : PT.product_step) : product_step_ir =
  {
    src =
      {
        prog_state = step.src.prog_state;
        assume_state_index = step.src.assume_state;
        guarantee_state_index = step.src.guarantee_state;
      };
    dst =
      {
        prog_state = step.dst.prog_state;
        assume_state_index = step.dst.assume_state;
        guarantee_state_index = step.dst.guarantee_state;
      };
    program_transition_id = program_transition_id_of_step ~reactive_program step;
    program_transition = (step.prog_transition.src_state, step.prog_transition.dst_state);
    program_guard = step.prog_guard;
    assume_edge =
      (let src, _guard, dst = step.assume_edge in
       { src_index = src; dst_index = dst; guard = step.assume_guard });
    guarantee_edge =
      (let src, _guard, dst = step.guarantee_edge in
       { src_index = src; dst_index = dst; guard = step.guarantee_guard });
    step_kind =
      (match step.step_class with
      | PT.Safe -> StepSafe
      | PT.Bad_assumption -> StepBadAssumption
      | PT.Bad_guarantee -> StepBadGuarantee);
    step_origin = StepFromExplicitExploration;
  }

let is_feasible_product_step ~(node : Abs.node_ir) ~(analysis : Temporal_automata.node_data)
    (step : product_step_ir) : bool =
  ignore node;
  step.src.assume_state_index <> analysis.assume_bad_idx
  && step.src.guarantee_state_index <> analysis.guarantee_bad_idx

let synthesize_fallback_product_steps ~(program_transitions : Abs.transition list)
    ~(node : Abs.node_ir) ~(analysis : Temporal_automata.node_data)
    ~(reactive_program : reactive_program_ir) ~(live_states : PT.product_state list)
    ~automaton_guard_fo ~product_state_of_pt:_ ~product_step_kind_of_pt:_ ~is_live_state:_ :
    product_step_ir list =
  let live_states = List.sort_uniq PT.compare_state live_states in
  let assume_edges =
    List.map
      (fun ((src, guard_raw, dst) : PT.automaton_edge) ->
        (src, dst, automaton_guard_fo guard_raw))
      analysis.assume_grouped_edges
  in
  let guarantee_edges =
    List.map
      (fun ((src, guard_raw, dst) : PT.automaton_edge) ->
        (src, dst, automaton_guard_fo guard_raw))
      analysis.guarantee_grouped_edges
  in
  let matching_edges edges src dst =
    edges
    |> List.filter_map (fun (s, d, g) -> if s = src && d = dst then Some g else None)
    |> List.sort_uniq Stdlib.compare
  in
  let transition_id_for ~(src : ident) ~(dst : ident) ~(guard : Core_syntax.hexpr) =
    match
      List.find_opt
        (fun (tr : reactive_transition_ir) ->
          String.equal tr.src_state src
          && String.equal tr.dst_state dst
          && simplify_fo tr.guard = simplify_fo guard)
        reactive_program.transitions
    with
    | Some tr -> tr.transition_id
    | None ->
        failwith
          (Printf.sprintf
             "Unable to associate fallback product step %s->%s with a reactive transition in node %s"
             src dst reactive_program.node_name)
  in
  program_transitions
  |> List.concat_map (fun (t : Abs.transition) ->
         let program_guard =
           match t.guard_expr with
           | None -> mk_hbool true
           | Some g -> simplify_fo (fo_of_expr g)
         in
         live_states
         |> List.filter (fun (st : PT.product_state) -> st.prog_state = t.src_state)
         |> List.concat_map (fun (src : PT.product_state) ->
                live_states
                |> List.filter (fun (st : PT.product_state) -> st.prog_state = t.dst_state)
                |> List.filter_map (fun (dst : PT.product_state) ->
                       let assume_guards = matching_edges assume_edges src.assume_state dst.assume_state in
                       let guarantee_guards =
                         matching_edges guarantee_edges src.guarantee_state dst.guarantee_state
                       in
                       let assume_guard =
                         match assume_guards with
                         | [] -> None
                         | [ g ] -> Some g
                         | g :: gs -> Some (List.fold_left mk_hor g gs)
                       in
                       let guarantee_guard =
                         match guarantee_guards with
                         | [] -> None
                         | [ g ] -> Some g
                         | g :: gs -> Some (List.fold_left mk_hor g gs)
                       in
                       match (assume_guard, guarantee_guard) with
                       | Some ag, Some gg ->
                           Some
                             {
                               src =
                                 {
                                   prog_state = src.prog_state;
                                   assume_state_index = src.assume_state;
                                   guarantee_state_index = src.guarantee_state;
                                 };
                               dst =
                                 {
                                   prog_state = dst.prog_state;
                                   assume_state_index = dst.assume_state;
                                   guarantee_state_index = dst.guarantee_state;
                                 };
                               program_transition_id =
                                 transition_id_for ~src:t.src_state ~dst:t.dst_state
                                   ~guard:program_guard;
                               program_transition = (t.src_state, t.dst_state);
                               program_guard;
                               assume_edge =
                                 { src_index = src.assume_state; dst_index = dst.assume_state; guard = ag };
                               guarantee_edge =
                                 { src_index = src.guarantee_state; dst_index = dst.guarantee_state; guard = gg };
                               step_kind = StepSafe;
                               step_origin = StepFromFallbackSynthesis;
                             }
                       | _ -> None)))
