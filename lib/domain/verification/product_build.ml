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

module PT = Product_types
module Vm = Verification_model

let simplify_fo (f : Core_syntax.historical Core_syntax.hexpr) : Core_syntax.historical Core_syntax.hexpr =
  Core_fo_simplifier.simplify f

type automaton_view = {
  states : ltl list;
  transitions : Automaton_types.transition list;
  bad_idx : int;
}

let fo_of_expr (e : expr) : Core_syntax.historical Core_syntax.hexpr =
  hexpr_of_expr e |> Core_syntax.historical_of_history_free

let automaton_guard_fo (g : Automaton_types.guard) : Core_syntax.historical Core_syntax.hexpr =
  simplify_fo g

let program_guard_fo (t : Vm.program_step) : Core_syntax.historical Core_syntax.hexpr =
  (* Program guards are normalized before overlap checks so they are compared at
     the same boolean level as recovered automaton guards. *)
  match t.guard_expr with None -> mk_hbool true | Some g -> fo_of_expr g |> simplify_fo

let first_false_idx (states : ltl list) : int =
  let rec loop i = function
    | [] -> -1
    | LFalse :: _ -> i
    | _ :: tl -> loop (i + 1) tl
  in
  loop 0 states

let bad_indices (states : ltl list) : int list =
  states
  |> List.mapi (fun i st -> (i, st))
  |> List.filter_map (function i, LFalse -> Some i | _ -> None)

let validate_transition_index ~role ~kind ~state_count idx =
  if idx < 0 || idx >= state_count then
    failwith
      (Printf.sprintf
         "%s automaton has an out-of-range transition %s index %d (state count: %d)"
         role kind idx state_count)

let validate_non_empty_states ~role (automaton : Automaton_types.automaton) =
  if automaton.states = [] then
    failwith
      (Printf.sprintf
         "%s automaton has no states; product exploration requires initial \
          automaton state 0"
         role)

let validate_transition_indices ~role (automaton : Automaton_types.automaton) =
  let state_count = List.length automaton.states in
  List.iter
    (fun (src, _guard, dst) ->
      validate_transition_index ~role ~kind:"source" ~state_count src;
      validate_transition_index ~role ~kind:"destination" ~state_count dst)
    automaton.transitions

let validate_single_bad_state ~role (automaton : Automaton_types.automaton) =
  match bad_indices automaton.states with
  | [] | [ _ ] -> ()
  | _ ->
      failwith
        (Printf.sprintf
           "%s automaton has multiple bad states; expected at most one LFalse \
            state"
           role)

let validate_initial_state_non_bad ~role
    (automaton : Automaton_types.automaton) =
  if List.mem 0 (bad_indices automaton.states) then
    raise
      (Failure
         (Printf.sprintf
            "%s automaton has a bad initial state; the corresponding contract \
             formula has no satisfying trace"
            role))

let validate_bad_state_absorbing ~role
    (automaton : Automaton_types.automaton) =
  match bad_indices automaton.states with
  | [ bad_idx ] ->
      List.iter
        (fun (src, _guard, dst) ->
          if src = bad_idx && dst <> bad_idx then
            failwith
              (Printf.sprintf
                 "%s automaton bad state %d must be absorbing, but has a \
                  transition to %d"
                 role bad_idx dst))
        automaton.transitions
  | [] | _ :: _ :: _ -> ()

let validate_assumption_guard_targets (automaton : Automaton_types.automaton) =
  let targets = Hashtbl.create 32 in
  List.iter
    (fun (src, guard, dst) ->
      let guard_key = guard |> simplify_fo |> Core_fo_simplifier.key_of_hexpr in
      let key = (src, guard_key) in
      match Hashtbl.find_opt targets key with
      | None -> Hashtbl.add targets key dst
      | Some previous when previous = dst -> ()
      | Some previous ->
          failwith
            (Printf.sprintf
               "assumption automaton has same-guard transitions from state %d \
                to both %d and %d; product summaries identify assumption edges \
                by source and guard"
               src previous dst))
    automaton.transitions

let validate_automata_spec (build : Automaton_types.automata_spec) =
  validate_non_empty_states ~role:"assumption" build.assume_automaton;
  validate_non_empty_states ~role:"guarantee" build.guarantee_automaton;
  validate_transition_indices ~role:"assumption" build.assume_automaton;
  validate_transition_indices ~role:"guarantee" build.guarantee_automaton;
  validate_single_bad_state ~role:"assumption" build.assume_automaton;
  validate_single_bad_state ~role:"guarantee" build.guarantee_automaton;
  validate_initial_state_non_bad ~role:"assumption" build.assume_automaton;
  validate_initial_state_non_bad ~role:"guarantee" build.guarantee_automaton;
  validate_bad_state_absorbing ~role:"assumption" build.assume_automaton;
  validate_assumption_guard_targets build.assume_automaton

let make_assume_view (build : Automaton_types.automata_spec) : automaton_view =
  let automaton = build.assume_automaton in
  {
    states = automaton.states;
    transitions = automaton.transitions;
    bad_idx = first_false_idx automaton.states;
  }

let make_guarantee_view (build : Automaton_types.automata_spec) : automaton_view =
  {
    states = build.guarantee_automaton.states;
    transitions = build.guarantee_automaton.transitions;
    bad_idx = first_false_idx build.guarantee_automaton.states;
  }

let node_outgoing (program_transitions : Vm.program_step list) : (ident, Vm.program_step list) Hashtbl.t =
  let tbl = Hashtbl.create 16 in
  List.iter
    (fun (t : Vm.program_step) ->
      let prev = Hashtbl.find_opt tbl t.src_state |> Option.value ~default:[] in
      Hashtbl.replace tbl t.src_state (t :: prev))
    program_transitions;
  tbl

let automaton_outgoing (view : automaton_view) : (int * Automaton_types.transition list) list =
  let tbl = Hashtbl.create 16 in
  List.iter
    (fun (((src, _guard, _dst) as edge) : Automaton_types.transition) ->
      let prev = Hashtbl.find_opt tbl src |> Option.value ~default:[] in
      Hashtbl.replace tbl src (edge :: prev))
    view.transitions;
  Hashtbl.fold (fun src edges acc -> (src, edges) :: acc) tbl []

let edges_from_outgoing outgoing idx =
  List.assoc_opt idx outgoing |> Option.value ~default:[]

let state_label i states =
  match List.nth_opt states i with
  | Some s -> string_of_ltl s
  | None -> Printf.sprintf "<state %d?>" i

let classify_step ~(assume_bad_idx : int) ~(guarantee_bad_idx : int) (dst : PT.product_state) :
    PT.step_class =
  if assume_bad_idx >= 0 && dst.assume_state = assume_bad_idx then PT.Bad_assumption
  else if guarantee_bad_idx >= 0 && dst.guarantee_state = guarantee_bad_idx then PT.Bad_guarantee
  else PT.Safe

let analyze_node ~(build : Automaton_types.automata_spec) ~(node : Vm.node_model)
    ~(program_transitions : Vm.program_step list) : Temporal_automata.node_data =
  validate_automata_spec build;
  let assume = make_assume_view build in
  let guarantee = make_guarantee_view build in
  let prog_outgoing = node_outgoing program_transitions in
  let assume_outgoing = automaton_outgoing assume in
  let guarantee_outgoing = automaton_outgoing guarantee in
  let initial_state =
    { PT.prog_state = node.init_state; assume_state = 0; guarantee_state = 0 }
  in
  let seen = Hashtbl.create 64 in
  let q = Queue.create () in
  let states_rev = ref [] in
  let steps_rev = ref [] in
  let push_state st =
    if not (Hashtbl.mem seen st) then (
      Hashtbl.add seen st ();
      states_rev := st :: !states_rev;
      Queue.add st q)
  in
  push_state initial_state;
  while not (Queue.is_empty q) do
    let src = Queue.take q in
    let prog_edges = Hashtbl.find_opt prog_outgoing src.prog_state |> Option.value ~default:[] in
    let assume_edges = edges_from_outgoing assume_outgoing src.assume_state in
    let guarantee_edges = edges_from_outgoing guarantee_outgoing src.guarantee_state in
    List.iter
      (fun (prog_transition : Vm.program_step) ->
        let prog_guard = program_guard_fo prog_transition in
        List.iter
          (fun (((_assume_src, assume_guard_raw, assume_dst) as assume_edge) : Automaton_types.transition) ->
            let assume_guard = automaton_guard_fo assume_guard_raw in
            List.iter
              (fun (((_guarantee_src, guarantee_guard_raw, guarantee_dst) as guarantee_edge) :
                     Automaton_types.transition) ->
                let guarantee_guard = automaton_guard_fo guarantee_guard_raw in
                let dst =
                  {
                    PT.prog_state = prog_transition.dst_state;
                    assume_state = assume_dst;
                    guarantee_state = guarantee_dst;
                  }
                in
                let step_class =
                  classify_step ~assume_bad_idx:assume.bad_idx ~guarantee_bad_idx:guarantee.bad_idx dst
                in
                let step =
                  {
                    PT.src;
                    dst;
                    prog_transition;
                    prog_guard;
                    assume_edge;
                    assume_guard;
                    guarantee_edge;
                    guarantee_guard;
                    step_class;
                  }
                in
                steps_rev := step :: !steps_rev;
                push_state dst)
              guarantee_edges)
          assume_edges)
      prog_edges
  done;
  {
    exploration =
      {
        PT.initial_state;
        states = List.sort_uniq PT.compare_state (List.rev !states_rev);
        steps = List.rev !steps_rev;
      };
    assume_bad_idx = assume.bad_idx;
    guarantee_bad_idx = guarantee.bad_idx;
    guarantee_state_labels = List.mapi (fun i _ -> state_label i guarantee.states) guarantee.states;
    assume_state_labels = List.mapi (fun i _ -> state_label i assume.states) assume.states;
    guarantee_grouped_edges = guarantee.transitions;
    assume_grouped_edges = assume.transitions;
  }
