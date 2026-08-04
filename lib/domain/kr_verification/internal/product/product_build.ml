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
open Kr_domain_core_syntax

module PT = Kr_verification_product
module Vm = Kr_domain_core_model

let simplify_fo
    (f : Kr_domain_core_syntax.historical Kr_domain_core_syntax.hexpr) :
    Kr_domain_core_syntax.historical Kr_domain_core_syntax.hexpr =
  Kr_domain_core_formula_simplifier.simplify f

type validated_monitor = {
  monitor : Kr_verification_automata_types.deterministic_partial_monitor;
  outgoing : PT.monitor_successor list array;
}

type validated_automata_spec = {
  assume : validated_monitor;
  guarantee : validated_monitor;
}

let automaton_guard_fo
    (g : Kr_verification_automata_types.guard) :
    Kr_domain_core_syntax.historical Kr_domain_core_syntax.hexpr =
  simplify_fo g

let validate_historical_guards ~role
    (monitor : Kr_verification_automata_types.deterministic_partial_monitor) =
  let min_ticks =
    Kr_domain_core.Kr_domain_core_history.min_ticks_by_indexed_graph
      ~state_count:monitor.state_count
      ~initial_state:monitor.initial_state
      ~edges:
        (List.map
           (fun ((src, _guard, dst) : Kr_verification_automata_types.transition) ->
             (src, dst))
           monitor.transitions)
  in
  List.iter
    (fun ((src, guard, dst) : Kr_verification_automata_types.transition) ->
      match min_ticks.(src) with
      | None ->
          (* An edge whose source is structurally unreachable is never
             considered by the partial-monitor semantics. *)
          ()
      | Some available_depth ->
          let required_depth =
            Kr_domain_core.Kr_domain_core_history.required_depth_hexpr guard
          in
          if required_depth > available_depth then
            failwith
              (Printf.sprintf
                 "%s monitor transition %d -> %d reads history at depth %d, \
                  but its source state is reachable after only %d tick(s)"
                 role src dst required_depth available_depth))
    monitor.transitions

let validate_monitor_structure ~role
    (monitor : Kr_verification_automata_types.deterministic_partial_monitor) =
  let valid_index index =
    index >= 0 && index < monitor.state_count
  in
  if monitor.state_count <= 0 then
    invalid_arg
      (Printf.sprintf "%s monitor contains no state" role)
  else if not (valid_index monitor.initial_state) then
    invalid_arg
      (Printf.sprintf
         "%s monitor initial state %d is outside [0,%d)" role
         monitor.initial_state monitor.state_count)
  else
    match
      List.find_opt
        (fun (source, _guard, target) ->
          not (valid_index source && valid_index target))
        monitor.transitions
    with
    | None -> ()
    | Some (source, _guard, target) ->
        invalid_arg
          (Printf.sprintf
             "%s monitor transition %d -> %d references a state outside \
              [0,%d)"
             role source target monitor.state_count)

let index_outgoing
    (monitor : Kr_verification_automata_types.deterministic_partial_monitor) =
  let outgoing = Array.make monitor.state_count [] in
  List.iter
    (fun (source, guard, target) ->
      outgoing.(source) <-
        {
          PT.destination_state_index = target;
          guard = automaton_guard_fo guard;
        }
        :: outgoing.(source))
    monitor.transitions;
  Array.map List.rev outgoing

let validate_monitor ~role monitor =
  validate_monitor_structure ~role monitor;
  validate_historical_guards ~role monitor;
  { monitor; outgoing = index_outgoing monitor }

let validate_automata_spec
    (build : Kr_verification_automata_types.automata_spec) : validated_automata_spec =
  {
    assume =
      validate_monitor ~role:"assumption" build.assume_monitor;
    guarantee =
      validate_monitor ~role:"guarantee" build.guarantee_monitor;
  }

let successors_at monitor source_state_index =
  monitor.outgoing.(source_state_index)

let node_outgoing
    (program_transitions : Vm.program_step list) :
    (ident, Vm.program_step list) Hashtbl.t =
  let tbl = Hashtbl.create 16 in
  List.iter
    (fun (t : Vm.program_step) ->
      let prev = Hashtbl.find_opt tbl t.src_state |> Option.value ~default:[] in
      Hashtbl.replace tbl t.src_state (t :: prev))
    program_transitions;
  tbl

let analyze_node ~(build : validated_automata_spec)
    ~(node : Vm.node_model)
    ~(program_transitions : Vm.program_step list) :
    Kr_verification_temporal_automata.node_data =
  let assume = build.assume in
  let guarantee = build.guarantee in
  let prog_outgoing = node_outgoing program_transitions in
  let initial_state =
    {
      PT.prog_state = node.init_state;
      assume_state_index = assume.monitor.initial_state;
      guarantee_state_index = guarantee.monitor.initial_state;
    }
  in
  let seen = Hashtbl.create 64 in
  let q = Queue.create () in
  let prefixes_rev = ref [] in
  let push_state st =
    if not (Hashtbl.mem seen st) then (
      Hashtbl.add seen st ();
      Queue.add st q)
  in
  push_state initial_state;
  while not (Queue.is_empty q) do
    let src = Queue.take q in
    let prog_edges = Hashtbl.find_opt prog_outgoing src.prog_state |> Option.value ~default:[] in
    let assume_successors =
      successors_at assume src.assume_state_index
    in
    List.iter
      (fun (prog_transition : Vm.program_step) ->
        List.iter
          (fun
            (assume_successor : PT.monitor_successor)
          ->
            let guarantee_successors =
              successors_at guarantee
                src.guarantee_state_index
            in
            let prefix =
              {
                PT.prog_transition;
                assume_source_state_index =
                  src.assume_state_index;
                assume_successor;
                guarantee_source_state_index =
                  src.guarantee_state_index;
                guarantee_successors;
              }
            in
            List.iter
              (fun
                (guarantee_successor : PT.monitor_successor)
              ->
                push_state
                  (PT.successor_destination prefix
                     guarantee_successor))
              guarantee_successors;
            prefixes_rev := prefix :: !prefixes_rev)
          assume_successors)
      prog_edges
  done;
  {
    exploration =
      {
        PT.initial_state;
        prefixes = List.rev !prefixes_rev;
      };
    guarantee_monitor = build.guarantee.monitor;
    assume_monitor = build.assume.monitor;
  }
