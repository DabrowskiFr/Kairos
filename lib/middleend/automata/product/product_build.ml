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
open Generated_names
open Temporal_support
open Ast_pretty
open Fo_specs
open Ltl_valuation
open Fo_formula

module Abs = Ir
module PT = Product_types

let simplify_fo (f : Fo_formula.t) : Fo_formula.t =
  match Fo_z3_solver.simplify_fo_formula f with Some simplified -> simplified | None -> f

type automaton_view = {
  states : Ast.ltl list;
  grouped : Automaton_types.transition list;
  atom_map_exprs : (ident * iexpr) list;
  bad_idx : int;
}

type analysis = Product_analysis.analysis = {
  exploration : PT.exploration;
  assume_bad_idx : int;
  guarantee_bad_idx : int;
  guarantee_state_labels : string list;
  assume_state_labels : string list;
  guarantee_grouped_edges : Automaton_types.transition list;
  assume_grouped_edges : Automaton_types.transition list;
  guarantee_atom_map_exprs : (ident * iexpr) list;
  assume_atom_map_exprs : (ident * iexpr) list;
}

let fo_of_iexpr (e : iexpr) : Fo_formula.t = iexpr_to_fo_with_atoms [] e

let automaton_guard_fo ~(atom_map_exprs : (ident * iexpr) list) (g : Automaton_types.guard) : Fo_formula.t =
  let _ = atom_map_exprs in
  simplify_fo g

let program_guard_fo (t : Abs.transition) : Fo_formula.t =
  (* Program guards are normalized before overlap checks so they are compared at
     the same boolean level as recovered automaton guards. *)
  match t.guard_iexpr with None -> FTrue | Some g -> fo_of_iexpr g |> simplify_fo

let first_false_idx (states : Ast.ltl list) : int =
  let rec loop i = function
    | [] -> -1
    | LFalse :: _ -> i
    | _ :: tl -> loop (i + 1) tl
  in
  loop 0 states

let make_assume_view (build : Automaton_types.automata_build) : automaton_view =
  match (build.assume_automaton, build.assume_atoms) with
  | Some automaton, Some atoms ->
      {
        states = automaton.states;
        grouped = automaton.grouped;
        atom_map_exprs = atoms.atom_named_exprs;
        bad_idx = first_false_idx automaton.states;
      }
  | _ ->
      {
        states = [ LTrue ];
        grouped = [ (0, FTrue, 0) ];
        atom_map_exprs = [];
        bad_idx = -1;
      }

let make_guarantee_view (build : Automaton_types.automata_build) : automaton_view =
  {
    states = build.guarantee_automaton.states;
    grouped = build.guarantee_automaton.grouped;
    atom_map_exprs = build.atoms.atom_named_exprs;
    bad_idx = first_false_idx build.guarantee_automaton.states;
  }

let node_outgoing (program_transitions : Abs.transition list) : (ident, Abs.transition list) Hashtbl.t =
  let tbl = Hashtbl.create 16 in
  List.iter
    (fun (t : Abs.transition) ->
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
    view.grouped;
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

let analyze_node ~(build : Automaton_types.automata_build) ~(node : Abs.node_ir)
    ~(program_transitions : Abs.transition list) : analysis =
  let assume = make_assume_view build in
  let guarantee = make_guarantee_view build in
  let prog_outgoing = node_outgoing program_transitions in
  let assume_outgoing = automaton_outgoing assume in
  let guarantee_outgoing = automaton_outgoing guarantee in
  let initial_state =
    { PT.prog_state = node.context.semantics.sem_init_state; assume_state = 0; guarantee_state = 0 }
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
      (fun (prog_transition : Abs.transition) ->
        let prog_guard = program_guard_fo prog_transition in
        List.iter
          (fun (((_assume_src, assume_guard_raw, assume_dst) as assume_edge) : Automaton_types.transition) ->
            let assume_guard = automaton_guard_fo ~atom_map_exprs:assume.atom_map_exprs assume_guard_raw in
            List.iter
              (fun (((_guarantee_src, guarantee_guard_raw, guarantee_dst) as guarantee_edge) :
                     Automaton_types.transition) ->
                let guarantee_guard =
                  automaton_guard_fo ~atom_map_exprs:guarantee.atom_map_exprs guarantee_guard_raw
                in
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
    guarantee_grouped_edges = guarantee.grouped;
    assume_grouped_edges = assume.grouped;
    guarantee_atom_map_exprs = guarantee.atom_map_exprs;
    assume_atom_map_exprs = assume.atom_map_exprs;
  }
