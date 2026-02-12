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

[@@@ocaml.warning "-32"]

open Ast
open Ast_builders
open Support
open Automaton_core
open Fo_specs
open Fo_time
open Monitor_generation_atoms
open Monitor_generation_spec
open Monitor_generation

type monitor_build = Monitor_generation.monitor_generation_build

let monitor_state_type : string = "mon_state"
let monitor_state_name : string = "__mon_state"
let monitor_state_ctor (i : int) : string = Printf.sprintf "Mon%d" i
let monitor_state_expr (i : int) : iexpr = mk_var (monitor_state_ctor i)

type bool_like = BoolInt | BoolBool

let bool_like_vars ~(var_types : (ident * ty) list) (n : node) : (ident * bool_like) list =
  let table = Hashtbl.create 16 in
  let invalid = Hashtbl.create 16 in
  let add var value =
    if Hashtbl.mem invalid var then ()
    else
      let lst = Hashtbl.find_opt table var |> Option.value ~default:[] in
      if List.mem value lst then () else Hashtbl.replace table var (value :: lst)
  in
  let mark_invalid var = Hashtbl.replace invalid var () in
  let add_const var = function
    | `Int i -> if i = 0 || i = 1 then add var (`Int i) else mark_invalid var
    | `Bool b -> add var (`Bool b)
  in
  let record_atom = function
    | FRel (HNow a, r, HNow b) -> begin
        match (as_var a, as_var b, b.iexpr, a.iexpr) with
        | Some x, _, ILitInt i, _ -> add_const x (`Int i)
        | _, Some x, _, ILitInt i -> add_const x (`Int i)
        | Some x, _, ILitBool v, _ -> add_const x (`Bool v)
        | _, Some x, _, ILitBool v -> add_const x (`Bool v)
        | _ -> ()
      end
    | _ -> ()
  in
  let rec collect_fo = function
    | FTrue | FFalse -> ()
    | FRel _ as f -> record_atom f
    | FPred _ -> ()
    | FNot a -> collect_fo a
    | FAnd (a, b) | FOr (a, b) | FImp (a, b) ->
        collect_fo a;
        collect_fo b
  in
  let rec collect_ltl = function
    | LTrue | LFalse -> ()
    | LAtom a -> collect_fo a
    | LNot a | LX a | LG a -> collect_ltl a
    | LAnd (a, b) | LOr (a, b) | LImp (a, b) ->
        collect_ltl a;
        collect_ltl b
  in
  List.iter collect_ltl (n.assumes @ n.guarantees);
  List.iter (fun inv -> collect_fo inv.formula) n.attrs.invariants_state_rel;
  let decide var values =
    if Hashtbl.mem invalid var then None
    else
      match (List.assoc_opt var var_types, values) with
      | Some TBool, vals ->
          if List.exists (function `Int _ -> true | _ -> false) vals then None else Some BoolBool
      | Some TInt, vals ->
          if List.exists (function `Int i -> i <> 0 && i <> 1 | _ -> false) vals then None
          else if List.exists (function `Bool _ -> true | _ -> false) vals then None
          else Some BoolInt
      | _ -> None
  in
  Hashtbl.fold
    (fun var vals acc -> match decide var vals with Some kind -> (var, kind) :: acc | None -> acc)
    table []

(* NOTE: currently unused; kept for reference if we re-enable bool-like normalization. *)
let normalize_bool_atoms ~(bool_vars : (ident * bool_like) list) (n : node) : node =
  let bool_map = List.to_seq bool_vars |> Hashtbl.of_seq in
  let base_int x = FRel (HNow (mk_var x), REq, HNow (mk_int 1)) in
  let base_bool x = FRel (HNow (mk_var x), REq, HNow (mk_bool true)) in
  let var_lit f =
    match f with
    | FRel (HNow a, r, HNow b) -> begin
        match (as_var a, as_var b, a.iexpr, b.iexpr) with
        | Some x, _, _, ILitInt i -> Some (x, `Int i, r, `Left)
        | _, Some x, ILitInt i, _ -> Some (x, `Int i, r, `Right)
        | Some x, _, _, ILitBool b -> Some (x, `Bool b, r, `Left)
        | _, Some x, ILitBool b, _ -> Some (x, `Bool b, r, `Right)
        | _ -> None
      end
    | _ -> None
  in
  let rec norm_fo f =
    match var_lit f with
    | Some (x, `Int i, REq, _) -> begin
        match Hashtbl.find_opt bool_map x with
        | Some BoolInt -> if i = 0 then FNot (base_int x) else if i = 1 then base_int x else f
        | _ -> f
      end
    | Some (x, `Int i, RNeq, _) -> begin
        match Hashtbl.find_opt bool_map x with
        | Some BoolInt -> if i = 0 then base_int x else if i = 1 then FNot (base_int x) else f
        | _ -> f
      end
    | Some (x, `Bool b, REq, _) -> begin
        match Hashtbl.find_opt bool_map x with
        | Some BoolBool -> if b then base_bool x else FNot (base_bool x)
        | _ -> f
      end
    | Some (x, `Bool b, RNeq, _) -> begin
        match Hashtbl.find_opt bool_map x with
        | Some BoolBool -> if b then FNot (base_bool x) else base_bool x
        | _ -> f
      end
    | _ -> begin
        match f with
        | FNot a -> FNot (norm_fo a)
        | FAnd (a, b) -> FAnd (norm_fo a, norm_fo b)
        | FOr (a, b) -> FOr (norm_fo a, norm_fo b)
        | FImp (a, b) -> FImp (norm_fo a, norm_fo b)
        | _ -> f
      end
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
  let invariants_state_rel =
    List.map (fun inv -> { inv with formula = norm_fo inv.formula }) n.attrs.invariants_state_rel
  in
  let n =
    { n with assumes = List.map norm_ltl n.assumes; guarantees = List.map norm_ltl n.guarantees }
  in
  { n with attrs = { n.attrs with invariants_state_rel } }

let transform_node ~build:(_build : monitor_build) (n : Ast.node) : Ast.node =
  let var_types = List.map (fun v -> (v.vname, v.vty)) (n.inputs @ n.locals @ n.outputs) in
  let _bool_vars = bool_like_vars ~var_types n in
  n

let monitor_update_stmts (atom_map : (ident * iexpr) list)
    (states : Automaton_engine.residual_state list) (transitions : Automaton_engine.transition list)
    : stmt list =
  let mon = monitor_state_name in
  let is_true e = match e.iexpr with ILitBool true -> true | _ -> false in
  let is_false e = match e.iexpr with ILitBool false -> true | _ -> false in
  let rec chain = function
    | [] -> mk_stmt SSkip
    | (dst, cond) :: rest ->
        if is_true cond then mk_stmt (SAssign (mon, monitor_state_expr dst))
        else if is_false cond then chain rest
        else
          mk_stmt (SIf (cond, [ mk_stmt (SAssign (mon, monitor_state_expr dst)) ], [ chain rest ]))
  in
  let per_state =
    List.init (List.length states) (fun i -> i)
    |> List.map (fun i ->
        let dests =
          List.filter_map
            (fun (src, guard, dst) ->
              if src = i then
                let cond = Automaton_guard.guard_to_iexpr guard in
                let cond = inline_atoms_iexpr atom_map cond in
                Some (dst, cond)
              else None)
            transitions
        in
        let dests = List.sort_uniq compare dests in
        if dests = [] then (i, mk_stmt SSkip) else (i, chain dests))
  in
  let branches = List.map (fun (i, body) -> (monitor_state_ctor i, [ body ])) per_state in
  match branches with [] -> [] | _ -> [ mk_stmt (SMatch (mk_var mon, branches, [])) ]

let monitor_assert (bad_idx : int) : stmt list = if bad_idx < 0 then [] else []

let inline_fo_atoms (atom_map : (ident * iexpr) list) (f : fo) : fo =
  let tbl = Hashtbl.create 16 in
  List.iter (fun (id, ex) -> Hashtbl.replace tbl id ex) atom_map;
  let rec inline_iexpr (e : iexpr) =
    match e.iexpr with
    | IVar id -> begin
        match Hashtbl.find_opt tbl id with Some ex -> inline_iexpr ex | None -> e
      end
    | ILitInt _ | ILitBool _ -> e
    | IPar inner -> with_iexpr_desc e (IPar (inline_iexpr inner))
    | IUn (op, inner) -> with_iexpr_desc e (IUn (op, inline_iexpr inner))
    | IBin (op, a, b) -> with_iexpr_desc e (IBin (op, inline_iexpr a, inline_iexpr b))
  in
  let rec inline_hexpr = function
    | HNow e -> HNow (inline_iexpr e)
    | HPreK (e, k) -> HPreK (inline_iexpr e, k)
  in
  let rec go = function
    | (FTrue | FFalse) as f -> f
    | FRel (h1, r, h2) -> FRel (inline_hexpr h1, r, inline_hexpr h2)
    | FPred (id, hs) -> FPred (id, List.map inline_hexpr hs)
    | FNot a -> FNot (go a)
    | FAnd (a, b) -> FAnd (go a, go b)
    | FOr (a, b) -> FOr (go a, go b)
    | FImp (a, b) -> FImp (go a, go b)
  in
  go f

let inline_atoms_in_node (atom_map : (ident * iexpr) list) (n : node) : node =
  let inline_iexpr = inline_atoms_iexpr atom_map in
  let inline_hexpr = function
    | HNow e -> HNow (inline_iexpr e)
    | HPreK (e, k) -> HPreK (inline_iexpr e, k)
  in
  let inline_fo = inline_fo_atoms atom_map in
  let rec inline_ltl = function
    | (LTrue | LFalse) as f -> f
    | LAtom a -> LAtom (inline_fo a)
    | LNot a -> LNot (inline_ltl a)
    | LAnd (a, b) -> LAnd (inline_ltl a, inline_ltl b)
    | LOr (a, b) -> LOr (inline_ltl a, inline_ltl b)
    | LImp (a, b) -> LImp (inline_ltl a, inline_ltl b)
    | LX a -> LX (inline_ltl a)
    | LG a -> LG (inline_ltl a)
  in
  let rec inline_stmt (s : stmt) =
    match s.stmt with
    | SAssign (id, e) -> with_stmt_desc s (SAssign (id, inline_iexpr e))
    | SIf (c, t, e) ->
        with_stmt_desc s (SIf (inline_iexpr c, List.map inline_stmt t, List.map inline_stmt e))
    | SMatch (e, cases, dflt) ->
        let cases = List.map (fun (id, body) -> (id, List.map inline_stmt body)) cases in
        with_stmt_desc s (SMatch (inline_iexpr e, cases, List.map inline_stmt dflt))
    | SSkip -> with_stmt_desc s SSkip
    | SCall (id, args, outs) -> with_stmt_desc s (SCall (id, List.map inline_iexpr args, outs))
  in
  let inline_invariant_user (inv : invariant_user) : invariant_user =
    { inv with inv_expr = inline_hexpr inv.inv_expr }
  in
  let inline_invariant_state_rel (inv : invariant_state_rel) : invariant_state_rel =
    { inv with formula = inline_fo inv.formula }
  in
  let inline_transition (t : transition) : transition =
    let t =
      {
        t with
        attrs =
          {
            t.attrs with
            ghost = List.map inline_stmt t.attrs.ghost;
            monitor = List.map inline_stmt t.attrs.monitor;
          };
      }
    in
    {
      t with
      guard = Option.map inline_iexpr t.guard;
      requires = List.map (Ast_provenance.map_with_origin inline_fo) t.requires;
      ensures = List.map (Ast_provenance.map_with_origin inline_fo) t.ensures;
      body = List.map inline_stmt t.body;
    }
  in
  let n =
    {
      n with
      assumes = List.map inline_ltl n.assumes;
      guarantees = List.map inline_ltl n.guarantees;
      trans = List.map inline_transition n.trans;
    }
  in
  n |> fun n ->
  {
    n with
    attrs =
      {
        n.attrs with
        invariants_user = List.map inline_invariant_user n.attrs.invariants_user;
        invariants_state_rel = List.map inline_invariant_state_rel n.attrs.invariants_state_rel;
      };
  }

let add_state_invariants_to_transitions ~(invariants_state_rel : invariant_state_rel list)
    ?(log : (transition -> fo -> unit) option = None) ?(add_to_ensures : bool = true)
    (trans : transition list) : transition list =
  let add_unique f lst =
    if List.exists (fun fo -> fo.value = f) lst then lst
    else Ast_provenance.with_origin Compatibility f :: lst
  in
  let invs = invariants_state_rel in
  List.map
    (fun (t : transition) ->
      let reqs, ens =
        List.fold_left
          (fun (reqs, ens) inv ->
            let pre_ok = if inv.is_eq then t.src = inv.state else t.src <> inv.state in
            let post_ok = if inv.is_eq then t.dst = inv.state else t.dst <> inv.state in
            let reqs =
              if pre_ok then (
                Option.iter (fun l -> l t inv.formula) log;
                add_unique inv.formula reqs)
              else reqs
            in
            let ens =
              if add_to_ensures && post_ok then (
                Option.iter (fun l -> l t inv.formula) log;
                add_unique inv.formula ens)
              else ens
            in
            (reqs, ens))
          (t.requires, t.ensures) invs
      in
      { t with requires = reqs; ensures = ens })
    trans

let simplify_mon_state_implications (fs : fo_o list) : fo_o list =
  let mon = monitor_state_name in
  let mon_state_of_var v =
    if String.length v >= 3 && String.sub v 0 3 = "Mon" then Some v else None
  in
  let mon_state_eq = function
    | FRel (HNow a, REq, HNow b) -> begin
        match (as_var a, as_var b) with
        | Some va, Some vb ->
            if va = mon then mon_state_of_var vb else if vb = mon then mon_state_of_var va else None
        | _ -> None
      end
    | _ -> None
  in
  let mon_state_cond = function FImp (cond, _body) -> mon_state_eq cond | _ -> None in
  let eqs =
    fs |> List.filter_map (fun f -> mon_state_eq f.value) |> List.sort_uniq String.compare
  in
  match eqs with
  | [ st ] ->
      List.filter
        (fun f -> match mon_state_cond f.value with None -> true | Some st' -> st' = st)
        fs
  | _ -> fs

(* Sub-pass 1: inject executable monitor code into transitions. *)
let inject_monitor_code ~(monitor_updates : stmt list) ~(monitor_asserts : stmt list)
    (trans : transition list) : transition list =
  List.map
    (fun (t : transition) ->
      let monitor = t.attrs.monitor @ monitor_updates @ monitor_asserts in
      { t with attrs = { t.attrs with monitor } })
    trans

(* Sub-pass 2: add no-bad-state contracts on transitions. *)
let add_not_bad_state_contracts ?(log : (transition -> fo -> unit) option = None)
    ~(bad_state_fo_opt : fo option) (trans : transition list) : transition list =
  match bad_state_fo_opt with
  | None -> trans
  | Some bad_fo ->
      List.map
        (fun (t : transition) ->
          Option.iter (fun l -> l t bad_fo) log;
          {
            t with
            requires = t.requires @ [ Ast_provenance.with_origin Monitor bad_fo ];
            ensures = t.ensures @ [ Ast_provenance.with_origin Monitor bad_fo ];
          })
        trans

(* Sub-pass 3: add monitor/program compatibility requirements. *)
let add_monitor_compatibility_requires ?(log : (transition -> fo -> unit) option = None)
    ~(incoming_prev_fo_shifted : fo list) (trans : transition list) : transition list =
  if incoming_prev_fo_shifted = [] then trans
  else
    List.map
      (fun (t : transition) ->
        List.iter (fun f -> Option.iter (fun l -> l t f) log) incoming_prev_fo_shifted;
        let incoming_prev_o =
          List.map (Ast_provenance.with_origin Compatibility) incoming_prev_fo_shifted
        in
        { t with requires = t.requires @ incoming_prev_o })
      trans

let transform_node_monitor_with_info ~(build : monitor_build) (n : Ast.node) :
    Ast.node * Stage_info.monitor_info =
  let is_input = Ast_utils.is_input_of_node n in
  let debug_contracts =
    match Sys.getenv_opt "OBC2WHY3_DEBUG_MONITOR_CONTRACTS" with Some "1" -> true | _ -> false
  in
  let log_contract ~(reason : string) ~(t : transition) (f : fo) : unit =
    if debug_contracts then
      prerr_endline (Printf.sprintf "[monitor] %s %s->%s: %s" reason t.src t.dst (string_of_fo f))
  in
  let var_types = List.map (fun v -> (v.vname, v.vty)) (n.inputs @ n.locals @ n.outputs) in
  let _bool_vars = bool_like_vars ~var_types n in
  let atom_map_exprs = build.atoms.atom_named_exprs in
  let atom_names = build.atom_names in
  let atom_name_to_fo = List.map (fun (a, name) -> (name, a)) build.atoms.atom_map in
  let debug_incoming =
    match Sys.getenv_opt "OBC2WHY3_DEBUG_MONITOR_INCOMING" with Some "1" -> true | _ -> false
  in
  if Automaton_core.monitor_log_enabled || debug_incoming then
    prerr_endline (Printf.sprintf "[monitor] atoms=%d" (List.length atom_names));
  if Automaton_core.monitor_log_enabled || debug_incoming then
    prerr_endline (Printf.sprintf "[monitor] atoms=%d" (List.length atom_names));
  let monitor_local = { vname = monitor_state_name; vty = TCustom monitor_state_type } in
  let user_assumes = n.assumes in
  let user_guarantees = n.guarantees in
  let invariants_user = n.attrs.invariants_user in
  let invariants_state_rel = n.attrs.invariants_state_rel in
  let automaton = build.automaton in
  if Automaton_core.monitor_log_enabled || debug_incoming then (
    List.iteri
      (fun i f ->
        prerr_endline
          (Printf.sprintf "[monitor] state %s = %s" (monitor_state_ctor i) (Support.string_of_ltl f)))
      automaton.states_raw;
    List.iter
      (fun (src, guard, dst) ->
        let guard_str = Automaton_guard.guard_to_formula guard in
        prerr_endline
          (Printf.sprintf "[monitor] edge %s -> %s : %s" (monitor_state_ctor src)
             (monitor_state_ctor dst) guard_str))
      automaton.transitions_raw);
  if Automaton_core.monitor_log_enabled then
    prerr_endline (Printf.sprintf "[monitor] grouped edges=%d" (List.length automaton.grouped));
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
        (fun (t : transition) ->
          match (Hashtbl.find_opt state_index t.src, Hashtbl.find_opt state_index t.dst) with
          | Some i, Some j ->
              if not (List.mem j prog_out.(i)) then prog_out.(i) <- j :: prog_out.(i)
          | _ -> ())
        n.trans;
      let mon_out = Array.make n_mon [] in
      List.iter
        (fun (i, _guard, j) -> if not (List.mem j mon_out.(i)) then mon_out.(i) <- j :: mon_out.(i))
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
        let i, j = Queue.take q in
        List.iter
          (fun i' ->
            List.iter
              (fun j' ->
                if not visited.(i').(j') then (
                  visited.(i').(j') <- true;
                  Queue.add (i', j') q))
              mon_out.(j))
          prog_out.(i)
      done;
      let mk_or_fo acc f = match acc with None -> Some f | Some a -> Some (FOr (a, f)) in
      let mon_eq i = FRel (HNow (mk_var monitor_state_name), REq, HNow (monitor_state_expr i)) in
      List.mapi
        (fun si st_name ->
          let disj =
            let acc = ref None in
            for mi = 0 to n_mon - 1 do
              if visited.(si).(mi) then acc := mk_or_fo !acc (mon_eq mi)
            done;
            match !acc with Some f -> f |> ltl_of_fo |> simplify_ltl |> fo_of_ltl | None -> FFalse
          in
          { is_eq = true; state = st_name; formula = disj })
        n.states
  in
  let bad_idx =
    let rec find i = function [] -> -1 | LFalse :: _ -> i | _ :: tl -> find (i + 1) tl in
    find 0 states
  in
  let bad_state_fo_opt =
    if bad_idx < 0 then None
    else Some (FRel (HNow (mk_var monitor_state_name), RNeq, HNow (monitor_state_expr bad_idx)))
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
          let cond = FRel (HNow (mk_var mon), REq, HNow (monitor_state_expr j)) in
          let guard_exprs =
            List.map Automaton_guard.guard_to_iexpr guards
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
        by_dst []
    in
    List.map (shift_fo_forward_inputs ~is_input) unshifted_in
  in
  let monitor_updates = monitor_update_stmts atom_map_exprs states grouped in
  let monitor_asserts = monitor_assert bad_idx in
  (* Explicitly sequence the monitor stage in 3 sub-passes: 1) monitor code injection, 2)
     no-bad-state contracts, 3) compatibility contracts. *)
  let trans = inject_monitor_code ~monitor_updates ~monitor_asserts n.trans in
  let trans =
    add_not_bad_state_contracts
      ~log:(Some (fun t f -> log_contract ~reason:"no_bad_state (require/ensure)" ~t f))
      ~bad_state_fo_opt trans
  in
  let trans =
    add_monitor_compatibility_requires
      ~log:(Some (fun t f -> log_contract ~reason:"monitor_pre (compat)" ~t f))
      ~incoming_prev_fo_shifted trans
  in
  let trans =
    add_state_invariants_to_transitions ~invariants_state_rel:compat_invariants
      ~log:(Some (fun t f -> log_contract ~reason:"compat_invariant" ~t f))
      ~add_to_ensures:false trans
  in
  let trans =
    List.map
      (fun (t : transition) ->
        {
          t with
          requires = simplify_mon_state_implications t.requires;
          ensures = simplify_mon_state_implications t.ensures;
        })
      trans
  in
  let n =
    {
      n with
      locals = n.locals @ [ monitor_local ];
      trans;
      assumes = user_assumes;
      guarantees = user_guarantees;
    }
  in
  let n = n |> fun n -> { n with attrs = { n.attrs with invariants_user; invariants_state_rel } } in
  let node = inline_atoms_in_node atom_map_exprs n in
  let info =
    {
      Stage_info.monitor_state_ctors = List.mapi (fun i _ -> monitor_state_ctor i) states;
      Stage_info.atom_count = List.length atom_names;
      Stage_info.warnings = [];
    }
  in
  (node, info)

let transform_node_monitor ~(build : monitor_build) (n : Ast.node) : Ast.node =
  let node, _info = transform_node_monitor_with_info ~build n in
  node
