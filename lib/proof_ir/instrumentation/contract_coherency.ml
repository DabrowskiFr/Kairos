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

let is_user_contract (f : ltl_o) : bool =
  match f.origin with Some UserContract -> true | _ -> false

let user_formulas (fs : ltl_o list) : ltl_o list = List.filter is_user_contract fs
let dedup_fo (xs : ltl list) : ltl list = List.sort_uniq compare xs
let instrumentation_state_var = "__aut_state"

let fo_atom_mentions_var (v : ident) (f : fo) : bool =
  let hexpr_mentions_var = function
    | HNow e | HPreK (e, _) -> begin
        match e.iexpr with
        | IVar v' -> String.equal v v'
        | _ -> false
      end
  in
  match f with
  | FRel (h1, _, h2) -> hexpr_mentions_var h1 || hexpr_mentions_var h2
  | FPred (_, hs) -> List.exists hexpr_mentions_var hs

let rec fo_ltl_mentions_var (v : ident) (f : ltl) : bool =
  match f with
  | LTrue | LFalse -> false
  | LAtom a -> fo_atom_mentions_var v a
  | LNot a | LX a | LG a -> fo_ltl_mentions_var v a
  | LAnd (a, b) | LOr (a, b) | LImp (a, b) | LW (a, b) ->
      fo_ltl_mentions_var v a || fo_ltl_mentions_var v b

let fo_mentions_var = fo_ltl_mentions_var

let collect_pre_k_fo (f : fo) : (ident * int) list =
  let from_hexpr = function
    | HNow _ -> []
    | HPreK (e, k) -> begin match e.iexpr with IVar v -> [ (v, k) ] | _ -> [] end
  in
  match f with
  | FRel (h1, _, h2) -> from_hexpr h1 @ from_hexpr h2
  | FPred (_id, hs) -> List.concat_map from_hexpr hs

let rec collect_pre_k_ltl (f : ltl) : (ident * int) list =
  match f with
  | LTrue | LFalse -> []
  | LAtom a -> collect_pre_k_fo a
  | LNot a | LX a | LG a -> collect_pre_k_ltl a
  | LAnd (a, b) | LOr (a, b) | LImp (a, b) | LW (a, b) ->
      collect_pre_k_ltl a @ collect_pre_k_ltl b

let min_step_by_state (n : node) : (ident, int) Hashtbl.t =
  let sem = n.semantics in
  let by_src = Hashtbl.create 16 in
  List.iter
    (fun (t : transition) ->
      let succ = Hashtbl.find_opt by_src t.src |> Option.value ~default:[] in
      Hashtbl.replace by_src t.src (t.dst :: succ))
    sem.sem_trans;
  let dist : (ident, int) Hashtbl.t = Hashtbl.create 16 in
  let q = Queue.create () in
  Hashtbl.replace dist sem.sem_init_state 0;
  Queue.add sem.sem_init_state q;
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

let min_step_by_state_monitor_aware (n : node) (automaton : Spot_automaton.automaton) :
    (ident, int) Hashtbl.t =
  let sem = n.semantics in
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
    Hashtbl.replace dist_pair (sem.sem_init_state, 0) 0;
    Hashtbl.replace dist_state sem.sem_init_state 0;
    Queue.add (sem.sem_init_state, 0) q);
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

let format_loc = function None -> "<unknown>" | Some l -> Printf.sprintf "%d:%d" l.line l.col

let validate_user_pre_k_definedness ?monitor_automaton (n : node) : unit =
  let min_step =
    match monitor_automaton with
    | None -> min_step_by_state n
    | Some a -> min_step_by_state_monitor_aware n a
  in
  let check_formula ~phase ~bound ~tr (foo : ltl_o) : string list =
    let pre_ks = collect_pre_k_ltl foo.value in
    pre_ks
    |> List.filter_map (fun (v, k) ->
        if k <= bound then None
        else
          Some
            (Printf.sprintf
               "node %s, transition %s->%s, %s at %s: pre_k(%s,%d) is not defined before step %d"
               n.semantics.sem_nname tr.src tr.dst phase (format_loc foo.loc) v k bound))
  in
  let errors =
    List.concat_map
      (fun (t : transition) ->
        match (Hashtbl.find_opt min_step t.src, Hashtbl.find_opt min_step t.dst) with
        | Some src_d, Some dst_d ->
            let req_errs =
              List.concat_map
                (check_formula ~phase:"require" ~bound:src_d ~tr:t)
                (user_formulas t.requires)
            in
            let ens_errs =
              List.concat_map
                (check_formula ~phase:"ensure" ~bound:dst_d ~tr:t)
                (user_formulas t.ensures)
            in
            req_errs @ ens_errs
        | _ -> [])
      n.semantics.sem_trans
  in
  match errors with
  | [] -> ()
  | _ ->
      let header =
        Printf.sprintf
          "invalid use of pre_k in transition contracts: history not yet defined on some phases"
      in
      failwith (header ^ "\n" ^ String.concat "\n" errors)

let shift_ltl_backward_inputs ~(is_input : ident -> bool) (f : ltl) : ltl =
  match f with
  | LAtom a -> LAtom (shift_fo_backward_inputs ~is_input a)
  | _ -> f

let user_ensures_by_target_state (n : node) : (ident, ltl list) Hashtbl.t =
  let by_dst = Hashtbl.create 16 in
  List.iter
    (fun (t : transition) ->
      let user_ens = Ast_provenance.values (user_formulas t.ensures) in
      if user_ens <> [] then
        let existing = Hashtbl.find_opt by_dst t.dst |> Option.value ~default:[] in
        Hashtbl.replace by_dst t.dst (dedup_fo (user_ens @ existing)))
      n.semantics.sem_trans;
  by_dst

let declared_state_invariants (n : node) : (ident, ltl list) Hashtbl.t =
  let by_state = Hashtbl.create 16 in
  List.iter
    (fun (inv : invariant_state_rel) ->
      if inv.is_eq
         && List.mem inv.state n.semantics.sem_states
         && not (fo_mentions_var instrumentation_state_var inv.formula)
      then
        let existing = Hashtbl.find_opt by_state inv.state |> Option.value ~default:[] in
        Hashtbl.replace by_state inv.state (dedup_fo (inv.formula :: existing)))
    n.specification.spec_invariants_state_rel;
  by_state

let state_invariant_from_node (n : node) : ident -> ltl option =
  let from_declared = declared_state_invariants n in
  let by_dst = user_ensures_by_target_state n in
  fun st ->
    let from_declared = Hashtbl.find_opt from_declared st |> Option.value ~default:[] in
    let from_ensures = Hashtbl.find_opt by_dst st |> Option.value ~default:[] in
    let all = dedup_fo (from_declared @ from_ensures) in
    conj_fo all

let add_state_invariants_in_attrs (n : node) ~(inv_of_state : ident -> ltl option) : node =
  let existing = n.specification.spec_invariants_state_rel in
  let has_inv st f =
    List.exists (fun inv -> inv.is_eq && inv.state = st && inv.formula = f) existing
  in
  let extra =
    n.semantics.sem_states
    |> List.filter_map (fun st ->
        match inv_of_state st with
        | None -> None
        | Some f when has_inv st f -> None
        | Some f -> Some { is_eq = true; state = st; formula = f })
  in
  if extra = [] then n
  else
    {
      n with
      specification = { n.specification with spec_invariants_state_rel = existing @ extra };
    }

let inject_state_invariant_contracts (n : node) ~(inv_of_state : ident -> ltl option) : node =
  let is_input = Ast_utils.is_input_of_node n in
  let shift_inv inv = shift_ltl_backward_inputs ~is_input inv in
  let add_unique_formula (origin : origin) (f : ltl) (xs : ltl_o list) : ltl_o list =
    if List.exists (fun (x : ltl_o) -> x.value = f) xs then xs
    else xs @ [ Ast_provenance.with_origin origin f ]
  in
  let trans =
    List.map
      (fun (t : transition) ->
        let requires =
          match inv_of_state t.src with
          | None -> t.requires
          | Some inv -> add_unique_formula Coherency inv t.requires
        in
        let ensures =
          match inv_of_state t.dst with
          | None -> t.ensures
          | Some inv -> add_unique_formula Coherency (shift_inv inv) t.ensures
        in
        if requires == t.requires && ensures == t.ensures then t else { t with requires; ensures })
      n.semantics.sem_trans
  in
  { n with semantics = { n.semantics with sem_trans = trans } }

let add_initial_invariant_goal (n : node) ~(inv_of_state : ident -> ltl option) : node =
  let is_input = Ast_utils.is_input_of_node n in
  match inv_of_state n.semantics.sem_init_state with
  | None -> n
  | Some inv ->
      let init_goal = shift_ltl_backward_inputs ~is_input inv in
      if fo_mentions_var instrumentation_state_var init_goal then n
      else Ast_utils.add_new_coherency_goals n [ init_goal ]

let ensure_next_requires (n : Ast.node) : Ast.node =
  let inv_of_state = state_invariant_from_node n in
  n
  |> inject_state_invariant_contracts ~inv_of_state
  |> add_state_invariants_in_attrs ~inv_of_state
  |> add_initial_invariant_goal ~inv_of_state

let user_contracts_coherency (n : Ast.node) : Ast.node = ensure_next_requires n
