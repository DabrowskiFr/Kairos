(*---------------------------------------------------------------------------
 * Tempo - synchronous runtime for OCaml
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
open Automaton_config
open Ltl_norm
open Ltl_progress
open Automaton_types
open Ltl_valuation

let build_residual_graph (atom_map:(fo * ident) list)
  (valuations:(string * bool) list list) (f0:ltl)
  : residual_state list * residual_transition list =
  let start_time = Sys.time () in
  let f0 = nnf_ltl f0 |> simplify_ltl in
  let tbl = Hashtbl.create 16 in
  let states = ref [] in
  let transitions = ref [] in
  let state_count = ref 0 in
  log_monitor "build residual graph: valuations=%d" (List.length valuations);
  let add_state f =
    let key = Support.string_of_ltl f in
    match Hashtbl.find_opt tbl key with
    | Some i -> (i, false)
    | None ->
        let i = List.length !states in
        states := !states @ [f];
        incr state_count;
        if !state_count mod 100 = 0 then
          log_monitor "states=%d transitions=%d"
            !state_count (List.length !transitions);
        if !state_count = 1000 || !state_count = 10000 then
          log_monitor "state threshold reached: %d" !state_count;
        Hashtbl.add tbl key i;
        (i, true)
  in
  let q = Queue.create () in
  let _ = add_state f0 in
  Queue.add f0 q;
  while not (Queue.is_empty q) do
    let f = Queue.take q in
    let i = Hashtbl.find tbl (Support.string_of_ltl f) in
    List.iter
      (fun vals ->
         let f' = progress_ltl atom_map vals f in
         let (j, is_new) = add_state f' in
         transitions := (i, vals, j) :: !transitions;
         if is_new then Queue.add f' q)
      valuations
  done;
  log_monitor "done: states=%d transitions=%d time=%.3fs"
    !state_count (List.length !transitions) (Sys.time () -. start_time);
  (!states, List.rev !transitions)

let group_transitions (transitions:residual_transition list)
  : grouped_transition list =
  let by_src = Hashtbl.create 16 in
  List.iter
    (fun (i, vals, j) ->
       let per_src =
         match Hashtbl.find_opt by_src i with
         | Some m -> m
         | None ->
             let m = Hashtbl.create 16 in
             Hashtbl.add by_src i m;
             m
       in
       let prev = Hashtbl.find_opt per_src j |> Option.value ~default:[] in
       Hashtbl.replace per_src j (vals :: prev))
    transitions;
  Hashtbl.fold
    (fun src per_src acc ->
       let items =
         Hashtbl.fold
           (fun dst vals_list acc -> (src, vals_list, dst) :: acc)
           per_src
           []
       in
       items @ acc)
    by_src
    []

let minimize_residual_graph (valuations:(string * bool) list list)
  (states:residual_state list) (transitions:residual_transition list)
  : residual_state list * residual_transition list =
  let n_states = List.length states in
  let val_index =
    let tbl = Hashtbl.create 16 in
    List.iteri (fun i v -> Hashtbl.add tbl (valuation_label v) i) valuations;
    tbl
  in
  let n_inputs = List.length valuations in
  let delta = Array.make_matrix n_states n_inputs 0 in
  List.iter
    (fun (i, vals, j) ->
       let key = valuation_label vals in
       match Hashtbl.find_opt val_index key with
       | Some k -> delta.(i).(k) <- j
       | None -> ())
    transitions;
  let is_accept i =
    match List.nth states i with
    | LFalse -> false
    | _ -> true
  in
  let class_of = Array.make n_states 0 in
  for i = 0 to n_states - 1 do
    class_of.(i) <- if is_accept i then 1 else 0
  done;
  let rec refine () =
    let table = Hashtbl.create n_states in
    let next_class = Array.make n_states 0 in
    let next_id = ref 0 in
    for i = 0 to n_states - 1 do
      let buf = Buffer.create 32 in
      Buffer.add_string buf (if is_accept i then "1|" else "0|");
      for k = 0 to n_inputs - 1 do
        Buffer.add_string buf (string_of_int class_of.(delta.(i).(k)));
        Buffer.add_char buf ','
      done;
      let key = Buffer.contents buf in
      match Hashtbl.find_opt table key with
      | Some id -> next_class.(i) <- id
      | None ->
          let id = !next_id in
          incr next_id;
          Hashtbl.add table key id;
          next_class.(i) <- id
    done;
    let changed = ref false in
    for i = 0 to n_states - 1 do
      if next_class.(i) <> class_of.(i) then changed := true
    done;
    Array.blit next_class 0 class_of 0 n_states;
    if !changed then refine () else ()
  in
  refine ();
  let class_count =
    Array.fold_left (fun acc x -> max acc (x + 1)) 0 class_of
  in
  let rep = Array.make class_count (-1) in
  for i = 0 to n_states - 1 do
    let c = class_of.(i) in
    if rep.(c) = -1 then rep.(c) <- i
  done;
  let new_states =
    List.init class_count (fun c -> List.nth states rep.(c))
  in
  let new_transitions = ref [] in
  for c = 0 to class_count - 1 do
    let s = rep.(c) in
    for k = 0 to n_inputs - 1 do
      let t = delta.(s).(k) in
      let c' = class_of.(t) in
      let vals = List.nth valuations k in
      new_transitions := (c, vals, c') :: !new_transitions
    done
  done;
  (new_states, List.rev !new_transitions)
