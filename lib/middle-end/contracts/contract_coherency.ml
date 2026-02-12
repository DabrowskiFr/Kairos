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
open Fo_specs
open Fo_time

let is_user_contract (f : fo_o) : bool =
  match f.origin with Some UserContract -> true | _ -> false

let user_formulas (fs : fo_o list) : fo_o list = List.filter is_user_contract fs

let rec collect_pre_k_fo (f : fo) : (ident * int) list =
  let from_hexpr = function
    | HNow _ -> []
    | HPreK (e, k) -> begin
        match e.iexpr with
        | IVar v -> [ (v, k) ]
        | _ -> []
      end
  in
  match f with
  | FTrue | FFalse -> []
  | FRel (h1, _, h2) -> from_hexpr h1 @ from_hexpr h2
  | FPred (_id, hs) -> List.concat_map from_hexpr hs
  | FNot a -> collect_pre_k_fo a
  | FAnd (a, b) | FOr (a, b) | FImp (a, b) -> collect_pre_k_fo a @ collect_pre_k_fo b

let min_step_by_state (n : node) : (ident, int) Hashtbl.t =
  let by_src = Hashtbl.create 16 in
  List.iter
    (fun (t : transition) ->
      let succ = Hashtbl.find_opt by_src t.src |> Option.value ~default:[] in
      Hashtbl.replace by_src t.src (t.dst :: succ))
    n.trans;
  let dist : (ident, int) Hashtbl.t = Hashtbl.create 16 in
  let q = Queue.create () in
  Hashtbl.replace dist n.init_state 0;
  Queue.add n.init_state q;
  while not (Queue.is_empty q) do
    let s = Queue.take q in
    let d = Hashtbl.find dist s in
    let succ = Hashtbl.find_opt by_src s |> Option.value ~default:[] in
    List.iter
      (fun s' ->
        if not (Hashtbl.mem dist s') then (
          Hashtbl.replace dist s' (d + 1);
          Queue.add s' q))
      succ
  done;
  dist

let min_step_by_state_monitor_aware (n : node) (automaton : Automaton_engine.automaton) :
    (ident, int) Hashtbl.t =
  let prog_succ = Ast_utils.transitions_from_state_fn n in
  let mon_count = List.length automaton.states in
  let mon_succ : int list array = Array.make mon_count [] in
  List.iter
    (fun (src, _guard, dst) ->
      if src >= 0 && src < mon_count && dst >= 0 && dst < mon_count then
        if not (List.mem dst mon_succ.(src)) then mon_succ.(src) <- dst :: mon_succ.(src))
    automaton.transitions;
  let dist_pair : (ident * int, int) Hashtbl.t = Hashtbl.create 64 in
  let dist_state : (ident, int) Hashtbl.t = Hashtbl.create 16 in
  let q = Queue.create () in
  if mon_count > 0 then (
    Hashtbl.replace dist_pair (n.init_state, 0) 0;
    Hashtbl.replace dist_state n.init_state 0;
    Queue.add (n.init_state, 0) q);
  while not (Queue.is_empty q) do
    let s, ms = Queue.take q in
    let d = Hashtbl.find dist_pair (s, ms) in
    List.iter
      (fun (t : transition) ->
        List.iter
          (fun ms' ->
            if not (Hashtbl.mem dist_pair (t.dst, ms')) then (
              Hashtbl.replace dist_pair (t.dst, ms') (d + 1);
              let prev = Hashtbl.find_opt dist_state t.dst in
              let next_d = d + 1 in
              (match prev with
              | None -> Hashtbl.replace dist_state t.dst next_d
              | Some old_d when next_d < old_d -> Hashtbl.replace dist_state t.dst next_d
              | Some _ -> ());
              Queue.add (t.dst, ms') q))
          mon_succ.(ms))
      (prog_succ s)
  done;
  dist_state

let format_loc = function
  | None -> "<unknown>"
  | Some l -> Printf.sprintf "%d:%d" l.line l.col

let validate_user_pre_k_definedness ?monitor_automaton (n : node) : unit =
  let min_step =
    match monitor_automaton with
    | None -> min_step_by_state n
    | Some a -> min_step_by_state_monitor_aware n a
  in
  let check_formula ~phase ~bound ~tr (foo : fo_o) : string list =
    let pre_ks = collect_pre_k_fo foo.value in
    pre_ks
    |> List.filter_map (fun (v, k) ->
           if k <= bound then None
           else
             Some
               (Printf.sprintf
                  "node %s, transition %s->%s, %s at %s: pre_k(%s,%d) is not defined before step %d"
                  n.nname tr.src tr.dst phase (format_loc foo.loc) v k bound))
  in
  let errors =
    List.concat_map
      (fun (t : transition) ->
        match Hashtbl.find_opt min_step t.src, Hashtbl.find_opt min_step t.dst with
        | Some src_d, Some dst_d ->
            let req_errs =
              List.concat_map (check_formula ~phase:"require" ~bound:src_d ~tr:t)
                (user_formulas t.requires)
            in
            let ens_errs =
              List.concat_map (check_formula ~phase:"ensure" ~bound:dst_d ~tr:t)
                (user_formulas t.ensures)
            in
            req_errs @ ens_errs
        | _ -> [])
      n.trans
  in
  match errors with
  | [] -> ()
  | _ ->
      let header =
        Printf.sprintf
          "invalid use of pre_k in transition contracts: history not yet defined on some phases"
      in
      failwith (header ^ "\n" ^ String.concat "\n" errors)

let succ_requires_by_state (n:node) : (ident, fo list) Hashtbl.t =
  (* Index successor requires by source state for quick lookup per dst. *)
  let tbl : (ident, fo list) Hashtbl.t = Hashtbl.create 16 in
  List.iter
    (fun (t:transition) ->
      List.iter
        (fun f ->
          let existing =
            Hashtbl.find_opt tbl (t.src)
            |> Option.value ~default:[]
          in
          Hashtbl.replace tbl (t.src) (f :: existing))
        (Ast_provenance.values (t.requires)))
    (n.trans);
  tbl

let updated_transitions ~(is_input:ident -> bool)
  ~(succ_requires_by_state:(ident, fo list) Hashtbl.t)
  (trans:transition list) : transition list =
  (* Add ensures derived from successor requires. *)
  let uniq lst =
    List.sort_uniq compare lst
  in
  List.map
    (fun (t:transition) ->
      let succ_reqs =
        Hashtbl.find_opt succ_requires_by_state (t.dst)
        |> Option.value ~default:[]
        |> uniq
      in
      let ensures_all = Ast_provenance.values (t.ensures) in
      let new_ensures =
        match conj_fo ensures_all with
        | None -> []
        | Some ensures_conj ->
            let shifted_req req =
              shift_fo_backward_inputs ~is_input req
            in
            let has_ensure f =
              List.exists (fun f' -> f' = f) ensures_all
            in
            succ_reqs
            |> List.map (fun req -> FImp (ensures_conj, shifted_req req))
            |> List.filter (fun f -> not (has_ensure f))
      in
      if new_ensures = [] then t
      else
        let new_ensures_o =
          List.map (Ast_provenance.with_origin Coherency) new_ensures
        in
        { t with
          ensures = t.ensures @ new_ensures_o; })
    trans

let ensure_next_requires (n:Ast.node) : Ast.node =
  let succ_requires_by_state = succ_requires_by_state n in
  let is_input v = List.exists (fun vi -> vi.vname = v) (n.inputs) in
  let trans =
    updated_transitions ~is_input ~succ_requires_by_state (n.trans)
  in
  { n with trans }

let user_contracts_coherency (n:Ast.node) : Ast.node =
  let is_input v = List.exists (fun vi -> vi.vname = v) (n.inputs) in
  let trans_indexed = List.mapi (fun i t -> (i, t)) (n.trans) in
  let by_src = Hashtbl.create 16 in
  List.iter
    (fun (i, t) ->
       let lst =
         Hashtbl.find_opt by_src (t.src) |> Option.value ~default:[]
       in
       Hashtbl.replace by_src (t.src) (i :: lst))
    trans_indexed;
  let user_requires =
    Array.of_list
      (List.map
         (fun (t:transition) -> Ast_provenance.values (user_formulas t.requires))
         (n.trans))
  in
  let user_ensures =
    Array.of_list
      (List.map
         (fun (t:transition) -> Ast_provenance.values (user_formulas t.ensures))
         (n.trans))
  in
  let shift_req f = shift_fo_backward_inputs ~is_input f in
  let add_coherency (i:int) (t:transition) =
    let antecedent = Option.value ~default:FTrue (conj_fo user_ensures.(i)) in
    let next =
      Hashtbl.find_opt by_src (t.dst) |> Option.value ~default:[]
    in
    let new_ensures =
      List.concat_map
        (fun j ->
           List.map (fun r -> FImp (antecedent, shift_req r)) user_requires.(j))
        next
    in
    if new_ensures = [] then t
    else
      let new_ensures_o =
        List.map (Ast_provenance.with_origin Coherency) new_ensures
      in
      { t with
        ensures = t.ensures @ new_ensures_o }
  in
  let trans =
    List.map (fun (i, t) -> add_coherency i t) trans_indexed
  in
  { n with trans }
