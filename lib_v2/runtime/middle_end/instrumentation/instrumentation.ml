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
open Automata_atoms
open Automata_spec
open Automata_generation

module Abs = Abstract_model
type build_ctx = Automata_generation.automata_build

let instrumentation_state_type : string = "aut_state"
let instrumentation_state_name : string = "__aut_state"
let state_ctor (i : int) : string = Printf.sprintf "Aut%d" i
let instrumentation_state_expr (i : int) : iexpr = mk_var (state_ctor i)

type bool_like = BoolInt | BoolBool

let bool_like_vars ~(var_types : (ident * ty) list) (n : node) : (ident * bool_like) list =
  let spec = Ast.specification_of_node n in
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
    | LAnd (a, b) | LOr (a, b) | LImp (a, b) | LW (a, b) ->
        collect_ltl a;
        collect_ltl b
  in
  List.iter collect_ltl (spec.spec_assumes @ spec.spec_guarantees);
  List.iter (fun inv -> collect_fo inv.formula) spec.spec_invariants_state_rel;
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
  let spec = Ast.specification_of_node n in
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
    | LW (a, b) -> LW (norm_ltl a, norm_ltl b)
  in
  let invariants_state_rel =
    List.map (fun inv -> { inv with formula = norm_fo inv.formula }) spec.spec_invariants_state_rel
  in
  let n =
    { n with assumes = List.map norm_ltl spec.spec_assumes; guarantees = List.map norm_ltl spec.spec_guarantees }
  in
  { n with attrs = { n.attrs with invariants_state_rel } }

let transform_node ~build:(_build : build_ctx) (n : Ast.node) : Ast.node =
  let var_types = List.map (fun v -> (v.vname, v.vty)) (n.inputs @ n.locals @ n.outputs) in
  let _bool_vars = bool_like_vars ~var_types n in
  n

let instrumentation_update_stmts (atom_map : (ident * iexpr) list)
    (states : Automaton_engine.residual_state list) (transitions : Automaton_engine.transition list)
    : stmt list =
  let mon = instrumentation_state_name in
  let is_true e = match e.iexpr with ILitBool true -> true | _ -> false in
  let is_false e = match e.iexpr with ILitBool false -> true | _ -> false in
  let rec chain = function
    | [] -> mk_stmt SSkip
    | (dst, cond) :: rest ->
        if is_true cond then mk_stmt (SAssign (mon, instrumentation_state_expr dst))
        else if is_false cond then chain rest
        else
          mk_stmt (SIf (cond, [ mk_stmt (SAssign (mon, instrumentation_state_expr dst)) ], [ chain rest ]))
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
  let branches = List.map (fun (i, body) -> (state_ctor i, [ body ])) per_state in
  match branches with [] -> [] | _ -> [ mk_stmt (SMatch (mk_var mon, branches, [])) ]

let instrumentation_assert (bad_idx : int) : stmt list = if bad_idx < 0 then [] else []

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
    | LW (a, b) -> LW (inline_ltl a, inline_ltl b)
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
            instrumentation = List.map inline_stmt t.attrs.instrumentation;
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
      assumes = List.map inline_ltl (Ast.specification_of_node n).spec_assumes;
      guarantees = List.map inline_ltl (Ast.specification_of_node n).spec_guarantees;
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
        invariants_state_rel =
          List.map inline_invariant_state_rel (Ast.specification_of_node n).spec_invariants_state_rel;
      };
  }

let add_state_invariants_to_transitions ~(invariants_state_rel : invariant_state_rel list)
    ?(log : (Abs.transition -> fo -> unit) option = None) ?(add_to_ensures : bool = true)
    (trans : Abs.transition list) : Abs.transition list =
  let add_unique f lst =
    if List.exists (fun fo -> fo.value = f) lst then lst
    else Ast_provenance.with_origin Compatibility f :: lst
  in
  let invs = invariants_state_rel in
  List.map
    (fun (t : Abs.transition) ->
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
  let mon = instrumentation_state_name in
  let mon_state_of_var v =
    if String.length v >= 3 && String.sub v 0 3 = "Aut" then Some v else None
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
let inject_instrumentation_code ~(instrumentation_updates : stmt list) ~(instrumentation_asserts : stmt list)
    (trans : Abs.transition list) : Abs.transition list =
  List.map
    (fun (t : Abs.transition) ->
      let instrumentation = t.attrs.instrumentation @ instrumentation_updates @ instrumentation_asserts in
      { t with attrs = { t.attrs with instrumentation } })
    trans

(* Sub-pass 2a: add no-bad-state requirements on transitions. *)
let add_not_bad_state_requires ?(log : (Abs.transition -> fo -> unit) option = None)
    ~(bad_state_fo_opt : fo option) (trans : Abs.transition list) : Abs.transition list =
  match bad_state_fo_opt with
  | None -> trans
  | Some bad_fo ->
      List.map
        (fun (t : Abs.transition) ->
          Option.iter (fun l -> l t bad_fo) log;
          { t with requires = t.requires @ [ Ast_provenance.with_origin Instrumentation bad_fo ] })
        trans

(* Sub-pass 2b: add no-bad-state obligations on transitions. *)
let add_not_bad_state_ensures ?(log : (Abs.transition -> fo -> unit) option = None)
    ~(bad_state_fo_opt : fo option) (trans : Abs.transition list) : Abs.transition list =
  match bad_state_fo_opt with
  | None -> trans
  | Some bad_fo ->
      List.map
        (fun (t : Abs.transition) ->
          Option.iter (fun l -> l t bad_fo) log;
          { t with ensures = t.ensures @ [ Ast_provenance.with_origin Instrumentation bad_fo ] })
        trans

(* Sub-pass 3: add monitor/program compatibility requirements. *)
let add_monitor_compatibility_requires ?(log : (Abs.transition -> fo -> unit) option = None)
    ~(incoming_prev_fo_shifted : fo list) (trans : Abs.transition list) : Abs.transition list =
  if incoming_prev_fo_shifted = [] then trans
  else
    List.map
      (fun (t : Abs.transition) ->
        List.iter (fun f -> Option.iter (fun l -> l t f) log) incoming_prev_fo_shifted;
        let incoming_prev_o =
          List.map (Ast_provenance.with_origin Compatibility) incoming_prev_fo_shifted
        in
        { t with requires = t.requires @ incoming_prev_o })
      trans

let compute_incoming_prev_fo_shifted ~(grouped : Automaton_engine.transition list)
    ~(atom_map_exprs : (ident * iexpr) list) ~(atom_name_to_fo : (ident * fo) list)
    ~(is_input : ident -> bool) : fo list =
  let mon = instrumentation_state_name in
  let by_dst = Hashtbl.create 16 in
  List.iter
    (fun (_i, guard, j) ->
      let prev = Hashtbl.find_opt by_dst j |> Option.value ~default:[] in
      Hashtbl.replace by_dst j (guard :: prev))
    grouped;
  let unshifted_in =
    Hashtbl.fold
      (fun j guards acc ->
        let cond = FRel (HNow (mk_var mon), REq, HNow (instrumentation_state_expr j)) in
        let guard_exprs =
          List.map Automaton_guard.guard_to_iexpr guards |> List.map (inline_atoms_iexpr atom_map_exprs)
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

let normalize_generated_contracts (trans : Abs.transition list) : Abs.transition list =
  List.map
    (fun (t : Abs.transition) ->
      {
        t with
        requires = simplify_mon_state_implications t.requires;
        ensures = simplify_mon_state_implications t.ensures;
      })
    trans

let drop_exact_formula (target : fo option) (trans : Abs.transition list) : Abs.transition list =
  match target with
  | None -> trans
  | Some target_fo ->
      let keep (f : fo_o) = f.value <> target_fo in
      List.map
        (fun (t : Abs.transition) ->
          { t with requires = List.filter keep t.requires; ensures = List.filter keep t.ensures })
        trans

let apply_contract_pipeline ~(n : Abs.node) ~(build : build_ctx)
    ~(analysis : Product_build.analysis) ~(instrumentation_updates : stmt list)
    ~(instrumentation_asserts : stmt list) ~(bad_state_fo_opt : fo option)
    ~(incoming_prev_fo_shifted : fo list) ~(compat_invariants : invariant_state_rel list)
    ~(log_contract : reason:string -> t:Abs.transition -> fo -> unit) : Abs.transition list =
  let trans = inject_instrumentation_code ~instrumentation_updates ~instrumentation_asserts n.trans in
  let trans =
    add_monitor_compatibility_requires
      ~log:(Some (fun t f -> log_contract ~reason:"Product/monitor_pre" ~t f))
      ~incoming_prev_fo_shifted trans
  in
  let trans =
    Product_contracts.add_assumption_projection_requires
      ~log:(Some (fun t f -> log_contract ~reason:"Product/assume_projection" ~t f))
      ~build ~analysis trans
  in
  let trans =
    add_state_invariants_to_transitions ~invariants_state_rel:compat_invariants
      ~log:(Some (fun t f -> log_contract ~reason:"Product/compat_invariant" ~t f))
      ~add_to_ensures:false trans
  in
  let trans =
    Product_contracts.add_bad_guarantee_projection_ensures
      ~log:(Some (fun t f -> log_contract ~reason:"Product/bad_guarantee_projection" ~t f))
      ~analysis trans
  in
  trans |> normalize_generated_contracts |> drop_exact_formula bad_state_fo_opt

let empty_instrumentation_info ~(states : Automaton_engine.residual_state list) ~(atom_names : ident list)
    : Stage_info.instrumentation_info =
  {
    Stage_info.state_ctors = List.mapi (fun i _ -> state_ctor i) states;
    Stage_info.atom_count = List.length atom_names;
    Stage_info.warnings = [];
    Stage_info.guarantee_automaton_lines = [];
    Stage_info.assume_automaton_lines = [];
    Stage_info.product_lines = [];
    Stage_info.obligations_lines = [];
    Stage_info.prune_lines = [];
    Stage_info.guarantee_automaton_dot = "";
    Stage_info.assume_automaton_dot = "";
    Stage_info.product_dot = "";
  }

type processing_context = {
  bad_idx : int;
  bad_state_fo_opt : fo option;
  incoming_prev_fo_shifted : fo list;
  instrumentation_updates : stmt list;
  instrumentation_asserts : stmt list;
}

type node_context = {
  is_input : ident -> bool;
  atom_map_exprs : (ident * iexpr) list;
  atom_names : ident list;
  atom_name_to_fo : (ident * fo) list;
  user_assumes : fo_ltl list;
  user_guarantees : fo_ltl list;
  invariants_user : invariant_user list;
  invariants_state_rel : invariant_state_rel list;
  states : Automaton_engine.residual_state list;
  transitions : Automaton_engine.transition list;
  grouped : Automaton_engine.transition list;
}

let build_processing_context ~(grouped : Automaton_engine.transition list)
    ~(states : Automaton_engine.residual_state list) ~(atom_map_exprs : (ident * iexpr) list)
    ~(atom_name_to_fo : (ident * fo) list) ~(is_input : ident -> bool) : processing_context =
  let bad_idx =
    let rec find i = function [] -> -1 | LFalse :: _ -> i | _ :: tl -> find (i + 1) tl in
    find 0 states
  in
  let bad_state_fo_opt =
    if bad_idx < 0 then None
    else Some (FRel (HNow (mk_var instrumentation_state_name), RNeq, HNow (instrumentation_state_expr bad_idx)))
  in
  let incoming_prev_fo_shifted =
    compute_incoming_prev_fo_shifted ~grouped ~atom_map_exprs ~atom_name_to_fo ~is_input
  in
  let instrumentation_updates = instrumentation_update_stmts atom_map_exprs states grouped in
  let instrumentation_asserts = instrumentation_assert bad_idx in
  { bad_idx; bad_state_fo_opt; incoming_prev_fo_shifted; instrumentation_updates; instrumentation_asserts }

let build_node_context ~(build : build_ctx) ~(n : Abs.node) : node_context =
  let input_names = List.map (fun (v : vdecl) -> v.vname) n.semantics.sem_inputs in
  let is_input (x : ident) = List.mem x input_names in
  let atom_map_exprs = build.atoms.atom_named_exprs in
  let atom_names = build.atom_names in
  let atom_name_to_fo = List.map (fun (a, name) -> (name, a)) build.atoms.atom_map in
  let user_assumes = n.specification.spec_assumes in
  let user_guarantees = n.specification.spec_guarantees in
  let invariants_user = n.attrs.invariants_user in
  let invariants_state_rel = n.specification.spec_invariants_state_rel in
  let automaton = build.automaton in
  let states = automaton.states in
  let transitions = automaton.transitions in
  let grouped = automaton.grouped in
  {
    is_input;
    atom_map_exprs;
    atom_names;
    atom_name_to_fo;
    user_assumes;
    user_guarantees;
    invariants_user;
    invariants_state_rel;
    states;
    transitions;
    grouped;
  }

let log_instrumentation_debug_info ~(ctx : node_context) ~(build : build_ctx)
    ~(debug_incoming : bool) : unit =
  let automaton = build.automaton in
  if Automaton_core.automata_log_enabled || debug_incoming then
    prerr_endline (Printf.sprintf "[automata] atoms=%d" (List.length ctx.atom_names));
  if Automaton_core.automata_log_enabled || debug_incoming then (
    List.iteri
      (fun i f ->
        prerr_endline
          (Printf.sprintf "[automata] state %s = %s" (state_ctor i) (Support.string_of_ltl f)))
      automaton.states_raw;
    List.iter
      (fun (src, guard, dst) ->
        let guard_str = Automaton_guard.guard_to_formula guard in
        prerr_endline
          (Printf.sprintf "[automata] edge %s -> %s : %s" (state_ctor src) (state_ctor dst)
             guard_str))
      automaton.transitions_raw);
  if Automaton_core.automata_log_enabled then
    prerr_endline (Printf.sprintf "[automata] grouped edges=%d" (List.length automaton.grouped))

let make_contract_logger () : (reason:string -> t:Abs.transition -> fo -> unit) =
  let debug_contracts =
    match Sys.getenv_opt "OBC2WHY3_DEBUG_MONITOR_CONTRACTS" with Some "1" -> true | _ -> false
  in
  fun ~(reason : string) ~(t : Abs.transition) (f : fo) ->
    if debug_contracts then
      prerr_endline (Printf.sprintf "[automata] %s %s->%s: %s" reason t.src t.dst (string_of_fo f))

let add_initial_automaton_support_goal ~(ctx : node_context) (n : Ast.node) : Ast.node =
  match ctx.states with
  | [] -> n
  | _ :: _ ->
      (* This goal is marked as an init-only coherency fact (FTrue -> body).
         The Why3 backend must interpret such goals under the concrete
         initialization guard, not as universally quantified facts over
         arbitrary pre-state valuations. *)
      let body =
        FRel
          ( HNow (mk_var instrumentation_state_name),
            REq,
            HNow (instrumentation_state_expr 0) )
      in
      Ast_utils.add_new_coherency_goals n [ FImp (FTrue, body) ]

let finalize_instrumented_node ~(ctx : node_context) ~(n : node) ~(trans : Abs.transition list) : node =
  let instrumentation_local = { vname = instrumentation_state_name; vty = TCustom instrumentation_state_type } in
  let n =
    {
      n with
      locals = n.locals @ [ instrumentation_local ];
      trans = List.map Abs.to_ast_transition trans;
      assumes = ctx.user_assumes;
      guarantees = ctx.user_guarantees;
    }
  in
  let n =
    {
      n with
      attrs = { n.attrs with invariants_user = ctx.invariants_user; invariants_state_rel = ctx.invariants_state_rel };
    }
  in
  let n = add_initial_automaton_support_goal ~ctx n in
  inline_atoms_in_node ctx.atom_map_exprs n

let finalize_instrumented_abstract_node ~(ctx : node_context) ~(n : Abs.node)
    ~(trans : Abs.transition list) : Abs.node =
  let n_ast = Abs.to_ast_node n in
  let node_ast = finalize_instrumented_node ~ctx ~n:n_ast ~trans in
  Abs.of_ast_node node_ast

let build_instrumented_transitions ~(build : build_ctx) ~(ctx : node_context)
    ~(n : Abs.node)
    ~(log_contract : reason:string -> t:Abs.transition -> fo -> unit) : Abs.transition list =
  let analysis = Product_build.analyze_node ~build ~node:n in
  let compat_invariants = Product_contracts.compat_invariants ~node:n ~analysis in
  let processing_ctx =
    build_processing_context ~grouped:ctx.grouped ~states:ctx.states
      ~atom_map_exprs:ctx.atom_map_exprs ~atom_name_to_fo:ctx.atom_name_to_fo ~is_input:ctx.is_input
  in
  apply_contract_pipeline ~n ~build ~analysis
    ~instrumentation_updates:processing_ctx.instrumentation_updates ~instrumentation_asserts:processing_ctx.instrumentation_asserts
    ~bad_state_fo_opt:processing_ctx.bad_state_fo_opt
    ~incoming_prev_fo_shifted:processing_ctx.incoming_prev_fo_shifted ~compat_invariants ~log_contract

let transform_abstract_node_with_info ~(build : build_ctx) (n : Abs.node) :
    Abs.node * Stage_info.instrumentation_info =
  let n_ast = Abs.to_ast_node n in
  let ctx = build_node_context ~build ~n in
  let log_contract = make_contract_logger () in
  let var_types = List.map (fun v -> (v.vname, v.vty)) (n_ast.inputs @ n_ast.locals @ n_ast.outputs) in
  let _bool_vars = bool_like_vars ~var_types n_ast in
  let debug_incoming =
    match Sys.getenv_opt "OBC2WHY3_DEBUG_MONITOR_INCOMING" with Some "1" -> true | _ -> false
  in
  log_instrumentation_debug_info ~ctx ~build ~debug_incoming;
  let product_analysis = Product_build.analyze_node ~build ~node:n in
  let trans =
    let compat_invariants = Product_contracts.compat_invariants ~node:n ~analysis:product_analysis in
    let processing_ctx =
      build_processing_context ~grouped:ctx.grouped ~states:ctx.states
        ~atom_map_exprs:ctx.atom_map_exprs ~atom_name_to_fo:ctx.atom_name_to_fo ~is_input:ctx.is_input
    in
    apply_contract_pipeline ~n ~build ~analysis:product_analysis
      ~instrumentation_updates:processing_ctx.instrumentation_updates
      ~instrumentation_asserts:processing_ctx.instrumentation_asserts
      ~bad_state_fo_opt:processing_ctx.bad_state_fo_opt
      ~incoming_prev_fo_shifted:processing_ctx.incoming_prev_fo_shifted ~compat_invariants ~log_contract
  in
  let node = finalize_instrumented_abstract_node ~ctx ~n ~trans in
  let rendered = Product_debug.render ~node_name:n.semantics.sem_nname ~analysis:product_analysis in
  let info =
    {
      (empty_instrumentation_info ~states:ctx.states ~atom_names:ctx.atom_names) with
      Stage_info.guarantee_automaton_lines = rendered.guarantee_automaton_lines;
      Stage_info.assume_automaton_lines = rendered.assume_automaton_lines;
      Stage_info.product_lines = rendered.product_lines;
      Stage_info.obligations_lines = rendered.obligations_lines;
      Stage_info.prune_lines = rendered.prune_lines;
      Stage_info.guarantee_automaton_dot = rendered.guarantee_automaton_dot;
      Stage_info.assume_automaton_dot = rendered.assume_automaton_dot;
      Stage_info.product_dot = rendered.product_dot;
    }
  in
  (node, info)

let transform_node_with_info ~(build : build_ctx) (n : Ast.node) :
    Ast.node * Stage_info.instrumentation_info =
  let node_abs, info = transform_abstract_node_with_info ~build (Abs.of_ast_node n) in
  (Abs.to_ast_node node_abs, info)

let transform_node ~(build : build_ctx) (n : Ast.node) : Ast.node =
  let node, _info = transform_node_with_info ~build n in
  node
