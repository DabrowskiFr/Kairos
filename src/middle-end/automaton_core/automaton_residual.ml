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
open Automaton_config
open Ltl_norm
open Ltl_progress
open Automaton_types
open Automaton_bdd

let merge_by_formula (items:(int * fo_ltl) list) : (int * fo_ltl) list =
  let tbl = Hashtbl.create 16 in
  List.iter
    (fun (guard, f) ->
       if guard <> bdd_false then
         let key = Support.string_of_ltl f in
         let prev = Hashtbl.find_opt tbl key in
         match prev with
         | None -> Hashtbl.add tbl key (guard, f)
         | Some (g, f') ->
             Hashtbl.replace tbl key (bdd_or g guard, f'))
    items;
  Hashtbl.fold (fun _ v acc -> v :: acc) tbl []

let progress_ltl_bdd ~(atom_map:(fo * ident) list)
  ~(index_tbl:(string, int) Hashtbl.t) (f:fo_ltl) : (int * fo_ltl) list =
  let rec go = function
    | LTrue -> [ (bdd_true, LTrue) ]
    | LFalse -> [ (bdd_true, LFalse) ]
    | LAtom a ->
        begin match List.assoc_opt a atom_map with
        | None -> [ (bdd_true, LFalse) ]
        | Some name ->
            let idx = Hashtbl.find index_tbl name in
            let var = bdd_var idx in
            [ (var, LTrue); (bdd_not var, LFalse) ]
        end
    | LNot a ->
        go a
        |> List.map (fun (g, f') -> (g, simplify_ltl (LNot f')))
        |> merge_by_formula
    | LAnd (a, b) ->
        let la = go a in
        let lb = go b in
        let combos =
          List.concat_map
            (fun (ga, fa) ->
               List.map
                 (fun (gb, fb) ->
                    let g = bdd_and ga gb in
                    (g, simplify_ltl (LAnd (fa, fb))))
                 lb)
            la
        in
        merge_by_formula combos
    | LOr (a, b) ->
        let la = go a in
        let lb = go b in
        let combos =
          List.concat_map
            (fun (ga, fa) ->
               List.map
                 (fun (gb, fb) ->
                    let g = bdd_and ga gb in
                    (g, simplify_ltl (LOr (fa, fb))))
                 lb)
            la
        in
        merge_by_formula combos
    | LImp (a, b) ->
        go (LOr (LNot a, b))
    | LX a ->
        [ (bdd_true, a) ]
    | LG a ->
        go a
        |> List.map (fun (g, f') -> (g, simplify_ltl (LAnd (f', LG a))))
        |> merge_by_formula
  in
  go f

let build_residual_graph_bdd ~(atom_map:(fo * ident) list)
  ~(atom_names:ident list) (f0:fo_ltl)
  : residual_state list * guarded_transition list =
  let start_time = Sys.time () in
  let f0 = nnf_ltl f0 |> simplify_ltl in
  let index_tbl = Hashtbl.create 16 in
  List.iteri (fun i name -> Hashtbl.add index_tbl name i) atom_names;
  let tbl = Hashtbl.create 16 in
  let states = ref [] in
  let transitions = ref [] in
  let state_count = ref 0 in
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
    let parts = progress_ltl_bdd ~atom_map ~index_tbl f in
    let by_dst = Hashtbl.create 16 in
    List.iter
      (fun (guard, f') ->
         if guard <> bdd_false then
           let (j, is_new) = add_state f' in
           let prev = Hashtbl.find_opt by_dst j |> Option.value ~default:bdd_false in
           Hashtbl.replace by_dst j (bdd_or prev guard);
           if is_new then Queue.add f' q)
      parts;
    Hashtbl.iter
      (fun j guard -> transitions := (i, guard, j) :: !transitions)
      by_dst
  done;
  log_monitor "done: states=%d transitions=%d time=%.3fs (bdd)"
    !state_count (List.length !transitions) (Sys.time () -. start_time);
  (!states, List.rev !transitions)

let minimize_residual_graph_bdd (states:residual_state list)
  (transitions:guarded_transition list)
  : residual_state list * guarded_transition list =
  let n_states = List.length states in
  let by_src = Hashtbl.create n_states in
  List.iter
    (fun (i, guard, j) ->
       let per_src =
         match Hashtbl.find_opt by_src i with
         | Some m -> m
         | None ->
             let m = Hashtbl.create 8 in
             Hashtbl.add by_src i m;
             m
       in
       let prev = Hashtbl.find_opt per_src j |> Option.value ~default:bdd_false in
       Hashtbl.replace per_src j (bdd_or prev guard))
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
      let per_src = Hashtbl.find_opt by_src i |> Option.value ~default:(Hashtbl.create 0) in
      let per_class = Hashtbl.create 8 in
      Hashtbl.iter
        (fun dst guard ->
           let c = class_of.(dst) in
           let prev = Hashtbl.find_opt per_class c |> Option.value ~default:bdd_false in
           Hashtbl.replace per_class c (bdd_or prev guard))
        per_src;
      let key_parts =
        Hashtbl.fold
          (fun c guard acc -> (c, guard) :: acc)
          per_class
          []
        |> List.sort (fun (a, _) (b, _) -> compare a b)
      in
      let buf = Buffer.create 64 in
      Buffer.add_string buf (if is_accept i then "1|" else "0|");
      List.iter
        (fun (c, guard) ->
           Buffer.add_string buf (string_of_int c);
           Buffer.add_char buf ':';
           Buffer.add_string buf (string_of_int guard);
           Buffer.add_char buf ',')
        key_parts;
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
  let new_transitions_tbl = Hashtbl.create 16 in
  Array.iteri
    (fun c s ->
       if s <> -1 then
         match Hashtbl.find_opt by_src s with
         | None -> ()
         | Some per_src ->
             Hashtbl.iter
               (fun dst guard ->
                  let c' = class_of.(dst) in
                  let key = (c, c') in
                  let prev =
                    Hashtbl.find_opt new_transitions_tbl key
                    |> Option.value ~default:bdd_false
                  in
                  Hashtbl.replace new_transitions_tbl key (bdd_or prev guard))
               per_src)
    rep;
  let new_transitions =
    Hashtbl.fold
      (fun (c, c') guard acc -> (c, guard, c') :: acc)
      new_transitions_tbl
      []
  in
  (new_states, new_transitions)
