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
open Specs
open Time_shit

let monitor_state_type : string = "mon_state"
let monitor_state_name : string = "__mon_state"
let monitor_state_ctor (i:int) : string = Printf.sprintf "Mon%d" i
let monitor_state_expr (i:int) : iexpr = IVar (monitor_state_ctor i)

let sanitize_ident (s:string) : string =
  let buf = Buffer.create (String.length s) in
  let add_underscore () =
    if Buffer.length buf = 0 || Buffer.nth buf (Buffer.length buf - 1) <> '_' then
      Buffer.add_char buf '_'
  in
  String.iter
    (fun c ->
       match c with
       | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' -> Buffer.add_char buf c
       | _ -> add_underscore ())
    s;
  let out = Buffer.contents buf in
  let out = String.lowercase_ascii out in
  let out =
    let len = String.length out in
    if len > 0 && out.[len - 1] = '_' then String.sub out 0 (len - 1) else out
  in
  let out = if out = "" then "atom" else out in
  let starts_with_digit =
    match out.[0] with '0' .. '9' -> true | _ -> false
  in
  if starts_with_digit then "atom_" ^ out else out

let make_atom_names (atom_exprs:(fo * iexpr) list) : string list =
  let used = Hashtbl.create 16 in
  let fresh base =
    let rec loop n =
      let name = if n = 0 then base else base ^ "_" ^ string_of_int n in
      if Hashtbl.mem used name then loop (n + 1)
      else (Hashtbl.add used name (); name)
    in
    loop 0
  in
  List.map
    (fun (_atom, expr) ->
       let base =
         "atom_" ^ sanitize_ident (Support.string_of_iexpr expr)
       in
       fresh base)
    atom_exprs

let rec iexpr_to_fo_with_atoms (atom_map:(ident * fo) list) (e:iexpr) : fo =
  match e with
  | ILitBool true -> FTrue
  | ILitBool false -> FFalse
  | ILitInt i -> FRel (HNow (ILitInt i), REq, HNow (ILitBool true))
  | IVar v ->
      begin match List.assoc_opt v atom_map with
      | Some f -> f
      | None -> FRel (HNow (IVar v), REq, HNow (ILitBool true))
      end
  | IPar e -> iexpr_to_fo_with_atoms atom_map e
  | IUn (Not, a) -> FNot (iexpr_to_fo_with_atoms atom_map a)
  | IBin (And, a, b) ->
      FAnd (iexpr_to_fo_with_atoms atom_map a, iexpr_to_fo_with_atoms atom_map b)
  | IBin (Or, a, b) ->
      FOr (iexpr_to_fo_with_atoms atom_map a, iexpr_to_fo_with_atoms atom_map b)
  | IBin (Eq, a, b) -> FRel (HNow a, REq, HNow b)
  | IBin (Neq, a, b) -> FRel (HNow a, RNeq, HNow b)
  | IBin (Lt, a, b) -> FRel (HNow a, RLt, HNow b)
  | IBin (Le, a, b) -> FRel (HNow a, RLe, HNow b)
  | IBin (Gt, a, b) -> FRel (HNow a, RGt, HNow b)
  | IBin (Ge, a, b) -> FRel (HNow a, RGe, HNow b)
  | IBin (_, a, b) ->
      FRel (HNow (IBin (Eq, a, b)), REq, HNow (ILitBool true))
  | IUn (_, a) ->
      FRel (HNow (IUn (Not, a)), REq, HNow (ILitBool true))

let inline_atoms_iexpr (atom_map:(ident * iexpr) list) (e:iexpr) : iexpr =
  let map = Hashtbl.create 16 in
  List.iter (fun (name, expr) -> Hashtbl.replace map name expr) atom_map;
  let rec go = function
    | IVar name ->
        begin match Hashtbl.find_opt map name with
        | Some expr -> expr
        | None -> IVar name
        end
    | ILitInt _ | ILitBool _ as e -> e
    | IPar e -> IPar (go e)
    | IUn (op, e) -> IUn (op, go e)
    | IBin (op, a, b) -> IBin (op, go a, go b)
  in
  go e

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
  let n = n in
  let fold_map = fold_map_for_node n in
  let pre_k_map = Collect.build_pre_k_infos n in
  let fold_internal_invariants =
    List.map
      (fun (h, acc) -> Invariant ("__fold_internal_" ^ acc, h))
      fold_map
  in
  let inputs = List.map (fun v -> v.vname) n.inputs in
  let atoms =
    collect_atoms_from_node n
    |> List.filter (fun a ->
           atom_to_iexpr ~inputs ~var_types ~fold_map ~pre_k_map a <> None)
    |> List.sort_uniq compare
  in
  if atoms = [] then n
  else
    let atom_exprs =
      List.filter_map
        (fun a ->
           match atom_to_iexpr ~inputs ~var_types ~fold_map ~pre_k_map a with
           | Some e -> Some (a, e)
           | None -> None)
        atoms
    in
    let atom_names = make_atom_names atom_exprs in
    let atom_map =
      List.map2 (fun (a, _) name -> (a, name)) atom_exprs atom_names
    in
    let atom_named_exprs =
      List.map2 (fun (_, e) name -> (name, e)) atom_exprs atom_names
    in
    let atom_locals =
      List.map (fun name -> { vname = name; vty = TBool }) atom_names
    in
    let atom_assigns =
      List.map
        (fun (a, name) ->
           match atom_to_iexpr ~inputs ~var_types ~fold_map ~pre_k_map a with
           | Some e -> SAssign (name, e)
           | None -> SSkip
        )
        atom_map
    in
    let atom_invariants =
      List.map (fun (name, e) -> Invariant (name, HNow e)) atom_named_exprs
    in
    let trans =
      List.map
        (fun (t:transition) ->
           let t = replace_atoms_transition atom_map t in
           let body = t.body @ atom_assigns in
           { t with body })
        n.trans
    in
    let assumes = List.map (replace_atoms_ltl atom_map) n.assumes in
    let guarantees = List.map (replace_atoms_ltl atom_map) n.guarantees in
    let invariants_mon = replace_atoms_invariants_mon atom_map n.invariants_mon in
    { n with
      locals = n.locals @ atom_locals;
      assumes;
      guarantees;
      invariants_mon = invariants_mon @ atom_invariants @ fold_internal_invariants;
      trans;
    }

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

let transform_node_monitor (n:node) : node =
  let init_for_var =
    let table =
      List.map (fun v -> (v.vname, v.vty)) (n.inputs @ n.locals @ n.outputs)
    in
    fun v ->
      match List.assoc_opt v table with
      | Some TBool -> ILitBool false
      | Some TInt -> ILitInt 0
      | Some TReal -> ILitInt 0
      | Some (TCustom _) | None -> ILitInt 0
  in
  let is_input v = List.exists (fun vd -> vd.vname = v) n.inputs in
  let var_types =
    List.map (fun v -> (v.vname, v.vty)) (n.inputs @ n.locals @ n.outputs)
  in
  let _bool_vars = bool_like_vars ~var_types n in
  let n = n in
  let fold_map = fold_map_for_node n in
  let pre_k_map = Collect.build_pre_k_infos n in
  let fold_internal_invariants =
    List.map
      (fun (h, acc) -> Invariant ("__fold_internal_" ^ acc, h))
      fold_map
  in
  let inputs = List.map (fun v -> v.vname) n.inputs in
  let atoms =
    collect_atoms_from_node n
    |> List.filter (fun a ->
           atom_to_iexpr ~inputs ~var_types ~fold_map ~pre_k_map a <> None)
    |> List.sort_uniq compare
  in
  let atom_exprs =
    List.filter_map
      (fun a ->
         match atom_to_iexpr ~inputs ~var_types ~fold_map ~pre_k_map a with
         | Some e -> Some (a, e)
         | None -> None)
      atoms
  in
  let atom_names = make_atom_names atom_exprs in
  let debug_incoming =
    match Sys.getenv_opt "OBC2WHY3_DEBUG_MONITOR_INCOMING" with
    | Some "1" -> true
    | _ -> false
  in
  if Automaton_core.monitor_log_enabled || debug_incoming then
    prerr_endline (Printf.sprintf "[monitor] atoms=%d" (List.length atom_names));
  if Automaton_core.monitor_log_enabled || debug_incoming then
    prerr_endline (Printf.sprintf "[monitor] atoms=%d" (List.length atom_names));
  let atom_map =
    List.map2 (fun (a, _) name -> (a, name)) atom_exprs atom_names
  in
  let atom_name_to_fo =
    List.map2 (fun (a, _) name -> (name, a)) atom_exprs atom_names
  in
  let atom_named_exprs =
    List.map2 (fun (_, e) name -> (name, e)) atom_exprs atom_names
  in
  let atom_map_exprs = atom_named_exprs in
  let monitor_local = { vname = monitor_state_name; vty = TCustom monitor_state_type } in
  let spec_assumes = List.map (replace_atoms_ltl atom_map) n.assumes in
  let spec_guarantees = List.map (replace_atoms_ltl atom_map) n.guarantees in
  let user_assumes = n.assumes in
  let user_guarantees = n.guarantees in
  let invariants_mon = n.invariants_mon in
  let spec =
    combine_contracts_for_monitor ~assumes:spec_assumes ~guarantees:spec_guarantees
    |> simplify_ltl
  in
  let valuations = enumerate_valuations atom_map atom_names in
  let states, transitions = build_residual_graph atom_map valuations spec in
  if Automaton_core.monitor_log_enabled || debug_incoming then (
    List.iteri
      (fun i f ->
         prerr_endline
           (Printf.sprintf "[monitor] state %s = %s"
              (monitor_state_ctor i) (Support.string_of_ltl f)))
      states;
    List.iter
      (fun (src, vals, dst) ->
         let guard_str = valuations_to_formula atom_names [vals] in
         prerr_endline
           (Printf.sprintf "[monitor] edge %s -> %s : %s"
              (monitor_state_ctor src) (monitor_state_ctor dst) guard_str))
      transitions
  );
  let states, transitions =
    minimize_residual_graph valuations states transitions
  in
  let grouped = group_transitions_bdd atom_names transitions in
  if Automaton_core.monitor_log_enabled then
    prerr_endline (Printf.sprintf "[monitor] grouped edges=%d" (List.length grouped));
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
        (fun (i, _vals, j) ->
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
  let incoming_prev_fo, incoming_prev_fo_shifted, outgoing_now_fo =
    let mon = monitor_state_name in
    let by_dst = Hashtbl.create 16 in
    let by_src = Hashtbl.create 16 in
    List.iter
      (fun (_i, guard, j) ->
         let prev = Hashtbl.find_opt by_dst j |> Option.value ~default:[] in
         Hashtbl.replace by_dst j (guard :: prev))
      grouped;
    List.iter
      (fun (i, guard, _j) ->
         let prev = Hashtbl.find_opt by_src i |> Option.value ~default:[] in
         Hashtbl.replace by_src i (guard :: prev))
      grouped;
    if debug_incoming then (
      let by_dst_with_src = Hashtbl.create 16 in
      List.iter
        (fun (src, guard, dst) ->
           let prev =
             Hashtbl.find_opt by_dst_with_src dst
             |> Option.value ~default:[]
           in
           Hashtbl.replace by_dst_with_src dst ((src, guard) :: prev))
        grouped;
      Hashtbl.iter
        (fun j guards ->
          let guard_exprs = List.map (bdd_to_iexpr atom_names) guards in
          let guard_fos = List.map (iexpr_to_fo_with_atoms atom_name_to_fo) guard_exprs in
          let guard_fos =
            List.map (shift_fo_forward_inputs ~init_for_var ~is_input) guard_fos
          in
          let guard_strs = List.map string_of_fo guard_fos in
          prerr_endline
            (Printf.sprintf "[monitor] incoming dst=%s guards=%s"
               (monitor_state_ctor j)
               (String.concat " OR " guard_strs)))
        by_dst;
      Hashtbl.iter
        (fun dst entries ->
           let lines =
             List.map
               (fun (src, guard) ->
                 let g =
                   bdd_to_iexpr atom_names guard
                   |> iexpr_to_fo_with_atoms atom_name_to_fo
                   |> shift_fo_forward_inputs ~init_for_var ~is_input
                   |> string_of_fo
                 in
                 Printf.sprintf "%s -> %s : %s"
                   (monitor_state_ctor src) (monitor_state_ctor dst) g)
               entries
           in
           prerr_endline
             (Printf.sprintf "[monitor] incoming edges dst=%s:\n  %s"
                (monitor_state_ctor dst)
                (String.concat "\n  " lines)))
        by_dst_with_src
    );
    let unshifted_in =
      Hashtbl.fold
        (fun j guards acc ->
         let cond =
           FRel (HNow (IVar mon), REq, HNow (monitor_state_expr j))
         in
         let guard_exprs = List.map (bdd_to_iexpr atom_names) guards in
         let guard_fos = List.map (iexpr_to_fo_with_atoms atom_name_to_fo) guard_exprs in
         let guard =
           match guard_fos with
           | [] -> FFalse
          | f :: rest -> List.fold_left (fun acc v -> FOr (acc, v)) f rest
         in
         FImp (cond, guard) :: acc)
        by_dst
        []
    in
    let shifted =
      List.map
        (shift_fo_forward_inputs ~init_for_var ~is_input)
        unshifted_in
    in
    let unshifted_out =
      Hashtbl.fold
        (fun i guards acc ->
         let cond =
           FRel (HNow (IVar mon), REq, HNow (monitor_state_expr i))
         in
         let guard_exprs = List.map (bdd_to_iexpr atom_names) guards in
         let guard_fos = List.map (iexpr_to_fo_with_atoms atom_name_to_fo) guard_exprs in
         let guard =
           match guard_fos with
           | [] -> FFalse
           | f :: rest -> List.fold_left (fun acc v -> FOr (acc, v)) f rest
         in
         FImp (cond, guard) :: acc)
        by_src
        []
    in
    (unshifted_in, shifted, unshifted_out)
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
               { t with
                 requires = t.requires @ [bad_fo];
                 ensures = t.ensures @ [bad_fo]; }
         in
         let t =
           let reqs =
             if incoming_prev_fo_shifted = [] then t.requires
             else t.requires @ incoming_prev_fo_shifted
           in
           let ens =
             if outgoing_now_fo = [] then t.ensures
             else t.ensures @ outgoing_now_fo
           in
           { t with requires = reqs; ensures = ens }
         in
         let body = t.body @ monitor_updates @ monitor_asserts in
         { t with body })
      n.trans
  in
  { n with
    locals = n.locals @ [monitor_local];
    assumes = user_assumes;
    guarantees = user_guarantees;
    invariants_mon =
      invariants_mon @ compat_invariants @ fold_internal_invariants;
    trans;
  }
