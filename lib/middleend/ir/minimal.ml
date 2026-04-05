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

module Abs = Ir
module PT = Product_types

let ( let* ) = Result.bind

let simplify_fo (f : Fo_formula.t) : Fo_formula.t =
  match Fo_z3_solver.simplify_fo_formula f with Some simplified -> simplified | None -> f

let product_state_of_pt (st : PT.product_state) : Abs.product_state =
  {
    prog_state = st.prog_state;
    assume_state_index = st.assume_state;
    guarantee_state_index = st.guarantee_state;
  }

let is_live_product_state ~(analysis : Product_build.analysis) (st : PT.product_state) : bool =
  st.assume_state <> analysis.assume_bad_idx && st.guarantee_state <> analysis.guarantee_bad_idx

let is_relevant_product_step ~(analysis : Product_build.analysis) (step : PT.product_step) : bool =
  is_live_product_state ~analysis step.src
  && (analysis.assume_bad_idx < 0 || step.dst.assume_state <> analysis.assume_bad_idx)

let classify_case ~(analysis : Product_build.analysis) (dst : PT.product_state) : PT.step_class =
  if analysis.assume_bad_idx >= 0 && dst.assume_state = analysis.assume_bad_idx then PT.Bad_assumption
  else if analysis.guarantee_bad_idx >= 0 && dst.guarantee_state = analysis.guarantee_bad_idx then
    PT.Bad_guarantee
  else PT.Safe

let transition_indices (program_transitions : Abs.transition list) : (Abs.transition, int) Hashtbl.t =
  program_transitions
  |> List.mapi (fun idx t -> (t, idx))
  |> List.to_seq |> Hashtbl.of_seq

let program_outgoing (program_transitions : Abs.transition list) : (ident, Abs.transition list) Hashtbl.t =
  let tbl = Hashtbl.create 16 in
  List.iter
    (fun (t : Abs.transition) ->
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

let product_transitions ~(analysis : Product_build.analysis) ~(program_transitions : Abs.transition list)
    ~(node : Abs.node_ir) :
    Abs.product_step_summary list =
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
  push_state analysis.exploration.initial_state;
  while not (Queue.is_empty q) do
    let src = Queue.take q in
    let prog_edges = Hashtbl.find_opt prog_outgoing src.prog_state |> Option.value ~default:[] in
    let assume_edges = edges_from_outgoing assume_outgoing src.assume_state in
    let guarantee_edges = edges_from_outgoing guarantee_outgoing src.guarantee_state in
    List.iter
      (fun (prog_transition : Abs.transition) ->
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
                             } : Abs.safe_product_case)
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
                             } : Abs.unsafe_product_case)
                      | PT.Safe | PT.Bad_assumption -> None)
             in
             Some
               ({
                 trace = { step_uid };
                 Abs.identity =
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
               } : Abs.product_step_summary))

type t = { summaries : Abs.product_step_summary list }

let build ~(node : Abs.node_ir) ~(analysis : Product_build.analysis)
    ~(program_transitions : Abs.transition list) : t =
  { summaries = product_transitions ~analysis ~program_transitions ~node }

let apply ~(minimal_generation : t) (n : Abs.node_ir) : Abs.node_ir =
  { n with summaries = minimal_generation.summaries }

let apply_program ~(minimal_generations : (Ast.ident * t) list) (p : Abs.node_ir list) :
    Abs.node_ir list =
  List.map
    (fun (n : Abs.node_ir) ->
      let minimal_generation =
        match List.assoc_opt n.context.semantics.sem_nname minimal_generations with
        | Some mg -> mg
        | None ->
            failwith
              (Printf.sprintf "Missing minimal generation for normalized node %s"
                 n.context.semantics.sem_nname)
      in
      apply ~minimal_generation n)
    p

let build_program ~(analyses : (Ast.ident * Product_build.analysis) list)
    ~(program_transitions_of_node : Ast.ident -> (Abs.transition list, string) result)
    (p : Abs.node_ir list) : ((Ast.ident * t) list, string) result =
  let rec collect acc = function
    | [] -> Ok (List.rev acc)
    | (n : Abs.node_ir) :: rest ->
        let* entry =
         let node_name = n.context.semantics.sem_nname in
         let* analysis =
           match List.assoc_opt node_name analyses with
           | Some analysis -> Ok analysis
           | None ->
               Error
                 (Printf.sprintf "Missing product analysis for normalized node %s" node_name)
         in
         let* program_transitions = program_transitions_of_node node_name in
         Ok (node_name, build ~node:n ~analysis ~program_transitions)
        in
        collect (entry :: acc) rest
  in
  collect [] p
