open Ast
open Formula_origin

module Abs = Normalized_program

let is_user_contract (f : Abs.contract_formula) : bool =
  match f.origin with Some UserContract -> true | _ -> false

let user_formulas (fs : Abs.contract_formula list) : Abs.contract_formula list = List.filter is_user_contract fs
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

let min_step_by_state (n : Abs.node) : (ident, int) Hashtbl.t =
  let sem = n.semantics in
  let by_src = Hashtbl.create 16 in
  List.iter
    (fun (t : Abs.transition) ->
      let succ = Hashtbl.find_opt by_src t.src |> Option.value ~default:[] in
      Hashtbl.replace by_src t.src (t.dst :: succ))
    n.trans;
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

let min_step_by_state_monitor_aware (n : Abs.node) (automaton : Spot_automaton.automaton) :
    (ident, int) Hashtbl.t =
  let sem = n.semantics in
  let by_src = Hashtbl.create 16 in
  List.iter
    (fun (t : Abs.transition) ->
      let ts = Hashtbl.find_opt by_src t.src |> Option.value ~default:[] in
      Hashtbl.replace by_src t.src (t :: ts))
    n.trans;
  let prog_succ src = Hashtbl.find_opt by_src src |> Option.value ~default:[] in
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
      (fun (t : Abs.transition) ->
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

let validate_user_pre_k_definedness ?monitor_automaton (n : Abs.node) : unit =
  let min_step =
    match monitor_automaton with
    | None -> min_step_by_state n
    | Some a -> min_step_by_state_monitor_aware n a
  in
  let check_formula ~phase ~bound ~(tr : Abs.transition) (foo : Abs.contract_formula) : string list =
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
      (fun (t : Abs.transition) ->
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
      n.trans
  in
  match errors with
  | [] -> ()
  | _ ->
      failwith
        ("invalid use of pre_k in transition contracts: history not yet defined on some phases\n"
        ^ String.concat "\n" errors)

let generate_transition_contracts (n : Abs.node) : Abs.node =
  let post_generation = Post_generation.build n in
  Pre_generation.apply ~post_generation n
