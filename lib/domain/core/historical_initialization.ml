(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frederic Dabrowski
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

let max_list = List.fold_left max 0

let rec required_depth_hexpr :
    type phase. phase hexpr -> int =
 fun h ->
  match h.hexpr with
  | HLitInt _ | HLitBool _ | HLitEnum _ | HVar _ -> 0
  | HPreK (_, k) -> k
  | HPred (_, args) | HFunCall (_, args) ->
      max_list (List.map required_depth_hexpr args)
  | HUn (_, inner) -> required_depth_hexpr inner
  | HBin (_, a, b) | HCmp (_, a, b) ->
      max (required_depth_hexpr a) (required_depth_hexpr b)

let required_depth_atom (a, _, b) =
  max (required_depth_hexpr a) (required_depth_hexpr b)

let rec required_depth_ltl = function
  | LTrue | LFalse -> 0
  | LAtom atom -> required_depth_atom atom
  | LNot a | LG a -> required_depth_ltl a
  | LX a -> max 0 (required_depth_ltl a - 1)
  | LAnd (a, b) | LOr (a, b) | LImp (a, b) | LW (a, b) ->
      max (required_depth_ltl a) (required_depth_ltl b)

let min_ticks_for_state min_ticks state =
  List.assoc_opt state min_ticks |> Option.join

let min_ticks_by_state (node : Verification_model.node_model) :
    (ident * int option) list =
  let distances : (ident, int) Hashtbl.t = Hashtbl.create 16 in
  let queue : (ident * int) Queue.t = Queue.create () in
  Hashtbl.add distances node.init_state 0;
  Queue.add (node.init_state, 0) queue;
  while not (Queue.is_empty queue) do
    let src, depth = Queue.take queue in
    node.steps
    |> List.iter (fun (step : Verification_model.program_step) ->
           if String.equal step.src_state src then
             let candidate = depth + 1 in
             match Hashtbl.find_opt distances step.dst_state with
             | Some previous when previous <= candidate -> ()
             | _ ->
                 Hashtbl.replace distances step.dst_state candidate;
                 Queue.add (step.dst_state, candidate) queue)
  done;
  node.states
  |> List.map (fun state -> (state, Hashtbl.find_opt distances state))
