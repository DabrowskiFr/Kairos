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

[@@@ocaml.warning "-32"]

open Ast
open Support
open Automaton_core
open Fo_specs
open Fo_time
open Monitor_atoms
open Monitor_spec
open Monitor_automaton

let monitor_state_type : string = "mon_state"
let monitor_state_name : string = "__mon_state"
let monitor_state_ctor (i:int) : string = Printf.sprintf "Mon%d" i
let monitor_state_expr (i:int) : iexpr = IVar (monitor_state_ctor i)

type monitor_atoms_stage = {
  node_atoms: node;
  atoms: monitor_atoms;
  atom_names: ident list;
  atom_map_exprs: (ident * iexpr) list;
  atom_name_to_fo: (ident * fo) list;
}

let pass_atoms (n:node) : monitor_atoms_stage =
  let atoms = collect_monitor_atoms n in
  let atom_names = List.map snd atoms.atom_map in
  let atom_map = atoms.atom_map in
  let node_atoms =
    {
      n with
      assumes = List.map (replace_atoms_ltl atom_map) n.assumes;
      guarantees = List.map (replace_atoms_ltl atom_map) n.guarantees;
      invariants_mon = replace_atoms_invariants_mon atom_map n.invariants_mon;
      trans = List.map (replace_atoms_transition atom_map) n.trans;
    }
  in
  let atom_map_exprs = atoms.atom_named_exprs in
  let atom_name_to_fo = List.map (fun (a, name) -> (name, a)) atom_map in
  { node_atoms; atoms; atom_names; atom_map_exprs; atom_name_to_fo }

let pass_build_automaton (stage:monitor_atoms_stage) : monitor_automaton =
  let spec = build_monitor_spec ~atom_map:stage.atoms.atom_map stage.node_atoms in
  build_monitor_automaton ~atom_map:stage.atoms.atom_map ~atom_names:stage.atom_names spec

let pass_inline_atoms (stage:monitor_atoms_stage) (n:node) : node =
  inline_atoms_in_node stage.atom_map_exprs n

type bool_like =
  | BoolInt
  | BoolBool

let bool_like_vars ~(var_types:(ident * ty) list) (n:node)
  : (ident * bool_like) list =
  let table = Hashtbl.create 16 in
  let invalid = Hashtbl.create 16 in
  let add var value =
    if Hashtbl.mem invalid var then ()
    else
      let lst = Hashtbl.find_opt table var |> Option.value ~default:[] in
      if List.mem value lst then ()
      else Hashtbl.replace table var (value :: lst)
  in
  let mark_invalid var = Hashtbl.replace invalid var () in
  let add_const var = function
    | `Int i ->
        if i = 0 || i = 1 then add var (`Int i) else mark_invalid var
    | `Bool b -> add var (`Bool b)
  in
  let record_atom = function
    | FRel (HNow (IVar x), REq, HNow (ILitInt i))
    | FRel (HNow (IVar x), RNeq, HNow (ILitInt i))
    | FRel (HNow (ILitInt i), REq, HNow (IVar x))
    | FRel (HNow (ILitInt i), RNeq, HNow (IVar x)) ->
        add_const x (`Int i)
    | FRel (HNow (IVar x), REq, HNow (ILitBool b))
    | FRel (HNow (IVar x), RNeq, HNow (ILitBool b))
    | FRel (HNow (ILitBool b), REq, HNow (IVar x))
    | FRel (HNow (ILitBool b), RNeq, HNow (IVar x)) ->
        add_const x (`Bool b)
    | _ -> ()
  in
  let rec collect_fo = function
    | FTrue | FFalse -> ()
    | FRel _ as f -> record_atom f
    | FPred _ -> ()
    | FNot a -> collect_fo a
    | FAnd (a, b) | FOr (a, b) | FImp (a, b) ->
        collect_fo a; collect_fo b
  in
  let rec collect_ltl = function
    | LTrue | LFalse -> ()
    | LAtom a -> collect_fo a
    | LNot a | LX a | LG a -> collect_ltl a
    | LAnd (a, b) | LOr (a, b) | LImp (a, b) ->
        collect_ltl a; collect_ltl b
  in
  List.iter collect_ltl (n.assumes @ n.guarantees);
  List.iter
    (function
      | InvariantStateRel (_is_eq, _st, f) -> collect_fo f
      | Invariant _ -> ())
    n.invariants_mon;
  let decide var values =
    if Hashtbl.mem invalid var then None
    else
      match List.assoc_opt var var_types, values with
      | Some TBool, vals ->
          if List.exists (function `Int _ -> true | _ -> false) vals then None
          else Some BoolBool
      | Some TInt, vals ->
          if List.exists (function `Int i -> i <> 0 && i <> 1 | _ -> false) vals then None
          else if List.exists (function `Bool _ -> true | _ -> false) vals then None
          else Some BoolInt
      | _ -> None
  in
  Hashtbl.fold
    (fun var vals acc ->
       match decide var vals with
       | Some kind -> (var, kind) :: acc
       | None -> acc)
    table
    []

(* NOTE: currently unused; kept for reference if we re-enable bool-like normalization. *)
let normalize_bool_atoms ~(bool_vars:(ident * bool_like) list) (n:node) : node =
  let bool_map = List.to_seq bool_vars |> Hashtbl.of_seq in
  let base_int x = FRel (HNow (IVar x), REq, HNow (ILitInt 1)) in
  let base_bool x = FRel (HNow (IVar x), REq, HNow (ILitBool true)) in
  let rec norm_fo f =
    match f with
    | FRel (HNow (IVar x), REq, HNow (ILitInt 0))
    | FRel (HNow (ILitInt 0), REq, HNow (IVar x)) ->
        begin match Hashtbl.find_opt bool_map x with
        | Some BoolInt -> FNot (base_int x)
        | _ -> f
        end
    | FRel (HNow (IVar x), RNeq, HNow (ILitInt 0))
    | FRel (HNow (ILitInt 0), RNeq, HNow (IVar x)) ->
        begin match Hashtbl.find_opt bool_map x with
        | Some BoolInt -> base_int x
        | _ -> f
        end
    | FRel (HNow (IVar x), REq, HNow (ILitInt 1))
    | FRel (HNow (ILitInt 1), REq, HNow (IVar x)) ->
        begin match Hashtbl.find_opt bool_map x with
        | Some BoolInt -> base_int x
        | _ -> f
        end
    | FRel (HNow (IVar x), RNeq, HNow (ILitInt 1))
    | FRel (HNow (ILitInt 1), RNeq, HNow (IVar x)) ->
        begin match Hashtbl.find_opt bool_map x with
        | Some BoolInt -> FNot (base_int x)
        | _ -> f
        end
    | FRel (HNow (IVar x), REq, HNow (ILitBool false))
    | FRel (HNow (ILitBool false), REq, HNow (IVar x)) ->
        begin match Hashtbl.find_opt bool_map x with
        | Some BoolBool -> FNot (base_bool x)
        | _ -> f
        end
    | FRel (HNow (IVar x), RNeq, HNow (ILitBool false))
    | FRel (HNow (ILitBool false), RNeq, HNow (IVar x)) ->
        begin match Hashtbl.find_opt bool_map x with
        | Some BoolBool -> base_bool x
        | _ -> f
        end
    | FRel (HNow (IVar x), REq, HNow (ILitBool true))
    | FRel (HNow (ILitBool true), REq, HNow (IVar x)) ->
        begin match Hashtbl.find_opt bool_map x with
        | Some BoolBool -> base_bool x
        | _ -> f
        end
    | FRel (HNow (IVar x), RNeq, HNow (ILitBool true))
    | FRel (HNow (ILitBool true), RNeq, HNow (IVar x)) ->
        begin match Hashtbl.find_opt bool_map x with
        | Some BoolBool -> FNot (base_bool x)
        | _ -> f
        end
    | FRel _ | FPred _ | FTrue | FFalse -> f
    | FNot a -> FNot (norm_fo a)
    | FAnd (a, b) -> FAnd (norm_fo a, norm_fo b)
    | FOr (a, b) -> FOr (norm_fo a, norm_fo b)
    | FImp (a, b) -> FImp (norm_fo a, norm_fo b)
  in
  let rec norm_ltl f =
    match f with
    | LTrue | LFalse -> f
    | LAtom a -> LAtom (norm_fo a)
    | LNot a -> LNot (norm_ltl a)
    | LAnd (a, b) -> LAnd (norm_ltl a, norm_ltl b)
    | LOr (a, b) -> LOr (norm_ltl a, norm_ltl b)
    | LImp (a, b) -> LImp (norm_ltl a, norm_ltl b)
    | LX a -> LX (norm_ltl a)
    | LG a -> LG (norm_ltl a)
  in
  let invariants_mon =
    List.map
      (function
        | Invariant (id, h) -> Invariant (id, h)
        | InvariantStateRel (is_eq, st, f) ->
            InvariantStateRel (is_eq, st, norm_fo f))
      n.invariants_mon
  in
  { n with
    assumes = List.map norm_ltl n.assumes;
    guarantees = List.map norm_ltl n.guarantees;
    invariants_mon; }

let transform_node (n:node) : node =
  let var_types =
    List.map (fun v -> (v.vname, v.vty)) (n.inputs @ n.locals @ n.outputs)
  in
  let _bool_vars = bool_like_vars ~var_types n in
  n

let monitor_update_stmts (atom_map:(ident * iexpr) list) (states:residual_state list)
  (transitions:guarded_transition list) : stmt list =
  let mon = monitor_state_name in
  let is_true = function ILitBool true -> true | _ -> false in
  let is_false = function ILitBool false -> true | _ -> false in
  let rec chain = function
    | [] -> SSkip
    | (dst, cond) :: rest ->
        if is_true cond then
          SAssign (mon, monitor_state_expr dst)
        else if is_false cond then
          chain rest
        else
          SIf (cond, [SAssign (mon, monitor_state_expr dst)], [chain rest])
  in
  let per_state =
    List.init (List.length states) (fun i -> i)
    |> List.map (fun i ->
      let dests =
        List.filter_map
          (fun (src, guard, dst) ->
             if src = i then
               let atom_names = List.map fst atom_map in
               let cond = bdd_to_iexpr atom_names guard in
               let cond = inline_atoms_iexpr atom_map cond in
               Some (dst, cond)
             else None)
          transitions
      in
      let dests = List.sort_uniq compare dests in
      if dests = [] then (i, SSkip) else (i, chain dests))
  in
  let branches =
    List.map
      (fun (i, body) -> (monitor_state_ctor i, [body]))
      per_state
  in
  match branches with
  | [] -> []
  | _ -> [SMatch (IVar mon, branches, [])]

let monitor_assert (bad_idx:int) : stmt list =
  if bad_idx < 0 then [] else []

let inline_fo_atoms (atom_map:(ident * iexpr) list) (f:fo) : fo =
  let tbl = Hashtbl.create 16 in
  List.iter (fun (id, ex) -> Hashtbl.replace tbl id ex) atom_map;
  let rec inline_iexpr = function
    | IVar id ->
        begin match Hashtbl.find_opt tbl id with
        | Some ex -> inline_iexpr ex
        | None -> IVar id
        end
    | ILitInt _ | ILitBool _ as e -> e
    | IPar e -> IPar (inline_iexpr e)
    | IUn (op, e) -> IUn (op, inline_iexpr e)
    | IBin (op, a, b) -> IBin (op, inline_iexpr a, inline_iexpr b)
  in
  let rec inline_hexpr = function
    | HNow e -> HNow (inline_iexpr e)
    | HPreK (e, k) -> HPreK (inline_iexpr e, k)
    | HFold (op, init, e) ->
        HFold (op, inline_iexpr init, inline_iexpr e)
  in
  let rec go = function
    | FTrue | FFalse as f -> f
    | FRel (h1, r, h2) -> FRel (inline_hexpr h1, r, inline_hexpr h2)
    | FPred (id, hs) -> FPred (id, List.map inline_hexpr hs)
    | FNot a -> FNot (go a)
    | FAnd (a, b) -> FAnd (go a, go b)
    | FOr (a, b) -> FOr (go a, go b)
    | FImp (a, b) -> FImp (go a, go b)
  in
  go f

let inline_atoms_in_node (atom_map:(ident * iexpr) list) (n:node) : node =
  let inline_iexpr = inline_atoms_iexpr atom_map in
  let inline_hexpr = function
    | HNow e -> HNow (inline_iexpr e)
    | HPreK (e, k) -> HPreK (inline_iexpr e, k)
    | HFold (op, init, e) ->
        HFold (op, inline_iexpr init, inline_iexpr e)
  in
  let inline_fo = inline_fo_atoms atom_map in
  let rec inline_ltl = function
    | LTrue | LFalse as f -> f
    | LAtom a -> LAtom (inline_fo a)
    | LNot a -> LNot (inline_ltl a)
    | LAnd (a, b) -> LAnd (inline_ltl a, inline_ltl b)
    | LOr (a, b) -> LOr (inline_ltl a, inline_ltl b)
    | LImp (a, b) -> LImp (inline_ltl a, inline_ltl b)
    | LX a -> LX (inline_ltl a)
    | LG a -> LG (inline_ltl a)
  in
  let rec inline_stmt = function
    | SAssign (id, e) -> SAssign (id, inline_iexpr e)
    | SIf (c, t, e) ->
        SIf (inline_iexpr c,
             List.map inline_stmt t,
             List.map inline_stmt e)
    | SMatch (e, cases, dflt) ->
        let cases =
          List.map
            (fun (id, body) -> (id, List.map inline_stmt body))
            cases
        in
        SMatch (inline_iexpr e, cases, List.map inline_stmt dflt)
    | SSkip -> SSkip
    | SCall (id, args, outs) ->
        SCall (id, List.map inline_iexpr args, outs)
  in
  let inline_invariant = function
    | Invariant (id, h) -> Invariant (id, inline_hexpr h)
    | InvariantStateRel (is_eq, st, f) ->
        InvariantStateRel (is_eq, st, inline_fo f)
  in
  let inline_transition (t:transition) : transition =
    {
      t with
      guard = Option.map inline_iexpr t.guard;
      requires = List.map inline_fo t.requires;
      ensures = List.map inline_fo t.ensures;
      lemmas = List.map inline_fo t.lemmas;
      ghost = List.map inline_stmt t.ghost;
      body = List.map inline_stmt t.body;
      monitor = List.map inline_stmt t.monitor;
    }
  in
  {
    n with
    assumes = List.map inline_ltl n.assumes;
    guarantees = List.map inline_ltl n.guarantees;
    invariants_mon = List.map inline_invariant n.invariants_mon;
    trans = List.map inline_transition n.trans;
  }

let add_state_invariants_to_transitions
  ~(invariants_mon:invariant_mon list)
  ?(log:(transition -> fo -> unit) option=None)
  ?(add_to_ensures:bool=true)
  (trans:transition list) : transition list =
  let add_unique f lst = if List.exists ((=) f) lst then lst else f :: lst in
  let invs =
    List.filter_map
      (function
        | InvariantStateRel (is_eq, st, f) -> Some (is_eq, st, f)
        | Invariant _ -> None)
      invariants_mon
  in
  List.map
    (fun (t:transition) ->
       let reqs, ens =
         List.fold_left
           (fun (reqs, ens) (is_eq, st, f) ->
              let pre_ok = if is_eq then t.src = st else t.src <> st in
              let post_ok = if is_eq then t.dst = st else t.dst <> st in
              let reqs =
                if pre_ok then (
                  Option.iter (fun l -> l t f) log;
                  add_unique f reqs
                ) else reqs
              in
              let ens =
                if add_to_ensures && post_ok then (
                  Option.iter (fun l -> l t f) log;
                  add_unique f ens
                ) else ens
              in
              (reqs, ens))
           (t.requires, t.ensures)
           invs
       in
       { t with requires = reqs; ensures = ens })
    trans

let simplify_mon_state_implications (fs:fo list) : fo list =
  let mon = monitor_state_name in
  let mon_state_of_var v = if String.length v >= 3 && String.sub v 0 3 = "Mon" then Some v else None in
  let mon_state_eq = function
    | FRel (HNow (IVar a), REq, HNow (IVar b)) ->
        if a = mon then mon_state_of_var b
        else if b = mon then mon_state_of_var a
        else None
    | _ -> None
  in
  let mon_state_cond = function
    | FImp (cond, _body) -> mon_state_eq cond
    | _ -> None
  in
  let eqs =
    fs
    |> List.filter_map mon_state_eq
    |> List.sort_uniq String.compare
  in
  match eqs with
  | [st] ->
      List.filter
        (fun f ->
           match mon_state_cond f with
           | None -> true
           | Some st' -> st' = st)
        fs
  | _ -> fs

let transform_node_monitor (n:node) : node =
  let is_input v = List.exists (fun vd -> vd.vname = v) n.inputs in
  let debug_contracts =
    match Sys.getenv_opt "OBC2WHY3_DEBUG_MONITOR_CONTRACTS" with
    | Some "1" -> true
    | _ -> false
  in
  let log_contract ~(reason:string) ~(t:transition) (f:fo) : unit =
    if debug_contracts then
      prerr_endline
        (Printf.sprintf "[monitor] %s %s->%s: %s"
           reason t.src t.dst (string_of_fo f))
  in
  let var_types =
    List.map (fun v -> (v.vname, v.vty)) (n.inputs @ n.locals @ n.outputs)
  in
  let _bool_vars = bool_like_vars ~var_types n in
  let stage = pass_atoms n in
  let n = stage.node_atoms in
  let atom_names = stage.atom_names in
  let debug_incoming =
    match Sys.getenv_opt "OBC2WHY3_DEBUG_MONITOR_INCOMING" with
    | Some "1" -> true
    | _ -> false
  in
  if Automaton_core.monitor_log_enabled || debug_incoming then
    prerr_endline (Printf.sprintf "[monitor] atoms=%d" (List.length atom_names));
  if Automaton_core.monitor_log_enabled || debug_incoming then
    prerr_endline (Printf.sprintf "[monitor] atoms=%d" (List.length atom_names));
  let atom_map = stage.atoms.atom_map in
  let atom_name_to_fo = stage.atom_name_to_fo in
  let atom_map_exprs = stage.atom_map_exprs in
  let monitor_local = { vname = monitor_state_name; vty = TCustom monitor_state_type } in
  let user_assumes = n.assumes in
  let user_guarantees = n.guarantees in
  let invariants_mon = n.invariants_mon in
  let automaton = pass_build_automaton stage in
  if Automaton_core.monitor_log_enabled || debug_incoming then (
    List.iteri
      (fun i f ->
         prerr_endline
           (Printf.sprintf "[monitor] state %s = %s"
              (monitor_state_ctor i) (Support.string_of_ltl f)))
      automaton.states_raw;
    List.iter
      (fun (src, guard, dst) ->
         let guard_str = bdd_to_formula atom_names guard in
         prerr_endline
           (Printf.sprintf "[monitor] edge %s -> %s : %s"
              (monitor_state_ctor src) (monitor_state_ctor dst) guard_str))
      automaton.transitions_raw
  );
  if Automaton_core.monitor_log_enabled then
    prerr_endline
      (Printf.sprintf "[monitor] grouped edges=%d"
         (List.length automaton.grouped));
  let states = automaton.states in
  let transitions = automaton.transitions in
  let grouped = automaton.grouped in
  let compat_invariants =
    let n_states = List.length n.states in
    let n_mon = List.length states in
    if n_states = 0 || n_mon = 0 then []
    else
      let state_index = Hashtbl.create n_states in
      List.iteri (fun i s -> Hashtbl.add state_index s i) n.states;
      let prog_out = Array.make n_states [] in
      List.iter
        (fun (t:transition) ->
           match Hashtbl.find_opt state_index t.src,
                 Hashtbl.find_opt state_index t.dst with
           | Some i, Some j ->
               if not (List.mem j prog_out.(i)) then
                 prog_out.(i) <- j :: prog_out.(i)
           | _ -> ())
        n.trans;
      let mon_out = Array.make n_mon [] in
      List.iter
        (fun (i, _guard, j) ->
           if not (List.mem j mon_out.(i)) then
             mon_out.(i) <- j :: mon_out.(i))
        transitions;
      let visited = Array.make_matrix n_states n_mon false in
      let q = Queue.create () in
      begin match Hashtbl.find_opt state_index n.init_state with
      | Some i0 ->
          visited.(i0).(0) <- true;
          Queue.add (i0, 0) q
      | None -> ()
      end;
      while not (Queue.is_empty q) do
        let (i, j) = Queue.take q in
        List.iter
          (fun i' ->
             List.iter
               (fun j' ->
                  if not visited.(i').(j') then (
                    visited.(i').(j') <- true;
                    Queue.add (i', j') q
                  ))
               mon_out.(j))
          prog_out.(i)
      done;
      let mk_or_fo acc f =
        match acc with
        | None -> Some f
        | Some a -> Some (FOr (a, f))
      in
      let mon_eq i =
        FRel (HNow (IVar monitor_state_name),
              REq,
              HNow (monitor_state_expr i))
      in
      List.mapi
        (fun si st_name ->
           let disj =
             let acc = ref None in
             for mi = 0 to n_mon - 1 do
               if visited.(si).(mi) then
                 acc := mk_or_fo !acc (mon_eq mi)
             done;
             match !acc with
             | Some f -> f |> ltl_of_fo |> simplify_ltl |> fo_of_ltl
             | None -> FFalse
           in
           InvariantStateRel (true, st_name, disj))
        n.states
  in
  let bad_idx =
    let rec find i = function
      | [] -> -1
      | LFalse :: _ -> i
      | _ :: tl -> find (i + 1) tl
    in
    find 0 states
  in
  let bad_state_fo_opt =
    if bad_idx < 0 then
      None
    else
      Some
        (FRel (HNow (IVar monitor_state_name),
               RNeq,
               HNow (monitor_state_expr bad_idx)))
  in
  let incoming_prev_fo_shifted =
    let mon = monitor_state_name in
    let by_dst = Hashtbl.create 16 in
    List.iter
      (fun (_i, guard, j) ->
         let prev = Hashtbl.find_opt by_dst j |> Option.value ~default:[] in
         Hashtbl.replace by_dst j (guard :: prev))
      grouped;
    let unshifted_in =
      Hashtbl.fold
        (fun j guards acc ->
         let cond =
           FRel (HNow (IVar mon), REq, HNow (monitor_state_expr j))
         in
         let guard_exprs =
           List.map (bdd_to_iexpr atom_names) guards
           |> List.map (inline_atoms_iexpr atom_map_exprs)
         in
         let guard_fos =
           List.map (iexpr_to_fo_with_atoms atom_name_to_fo) guard_exprs
           |> List.map (inline_fo_atoms atom_map_exprs)
         in
         let guard =
           match guard_fos with
           | [] -> FFalse
           | f :: rest -> List.fold_left (fun acc v -> FOr (acc, v)) f rest
         in
         FImp (cond, guard) :: acc)
        by_dst
        []
    in
    List.map (shift_fo_forward_inputs ~is_input) unshifted_in
  in
  let monitor_updates = monitor_update_stmts atom_map_exprs states grouped in
  let monitor_asserts = monitor_assert bad_idx in
  let trans =
    List.map
      (fun (t:transition) ->
         let t =
           match bad_state_fo_opt with
           | None -> t
           | Some bad_fo ->
               let () = log_contract ~reason:"no_bad_state (require)" ~t bad_fo in
               let () = log_contract ~reason:"no_bad_state (ensure)" ~t bad_fo in
               { t with
                 requires = t.requires @ [bad_fo];
                 ensures = t.ensures @ [bad_fo]; }
         in
         let t =
           let reqs =
             if incoming_prev_fo_shifted = [] then t.requires
             else (
               List.iter (log_contract ~reason:"monitor_pre (compat)" ~t)
                 incoming_prev_fo_shifted;
               t.requires @ incoming_prev_fo_shifted
             )
           in
           let ens = t.ensures in
           let reqs = List.map (inline_fo_atoms atom_map_exprs) reqs in
           let ens = List.map (inline_fo_atoms atom_map_exprs) ens in
           let lemmas = List.map (inline_fo_atoms atom_map_exprs) t.lemmas in
           { t with requires = reqs; ensures = ens; lemmas }
         in
         let monitor = t.monitor @ monitor_updates @ monitor_asserts in
         { t with monitor })
      n.trans
  in
  let trans =
    List.map
      (fun (t:transition) ->
         let reqs = List.map (inline_fo_atoms atom_map_exprs) t.requires in
         let ens = List.map (inline_fo_atoms atom_map_exprs) t.ensures in
         let lemmas = List.map (inline_fo_atoms atom_map_exprs) t.lemmas in
         { t with requires = reqs; ensures = ens; lemmas })
      trans
  in
  let trans =
    add_state_invariants_to_transitions
      ~invariants_mon:compat_invariants
      ~log:(Some (fun t f -> log_contract ~reason:"compat_invariant" ~t f))
      ~add_to_ensures:false
      trans
  in
  let trans =
    List.map
      (fun (t:transition) ->
         { t with
           requires = simplify_mon_state_implications t.requires;
           ensures = simplify_mon_state_implications t.ensures; })
      trans
  in
  let n =
    { n with
      locals = n.locals @ [monitor_local];
      assumes = user_assumes;
      guarantees = user_guarantees;
      invariants_mon = invariants_mon;
      trans;
    }
  in
  pass_inline_atoms stage n
