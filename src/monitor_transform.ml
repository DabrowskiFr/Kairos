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
open Support
open Automaton_core
open Specs

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

let transform_node (n:node) : node =
  let fold_map = fold_map_for_node n in
  let inputs = List.map (fun v -> v.vname) n.inputs in
  let var_types =
    List.map (fun v -> (v.vname, v.vty)) (n.inputs @ n.locals @ n.outputs)
  in
  let atoms =
    collect_atoms_from_node n
    |> List.filter (fun a -> atom_to_iexpr ~inputs ~var_types ~fold_map a <> None)
    |> List.sort_uniq compare
  in
  if atoms = [] then n
  else
    let atom_exprs =
      List.filter_map
        (fun a ->
           match atom_to_iexpr ~inputs ~var_types ~fold_map a with
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
           match atom_to_iexpr ~inputs ~var_types ~fold_map a with
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
      invariants_mon = invariants_mon @ atom_invariants;
      trans;
    }

let monitor_update_stmts (atom_names:ident list) (states:residual_state list)
  (transitions:residual_transition list) : stmt list =
  let mon = monitor_state_name in
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
      match Hashtbl.find_opt by_src i with
      | None -> (i, SSkip)
      | Some per_src ->
          let dests =
            Hashtbl.fold
              (fun dst vals_list acc ->
                 let cond = valuations_to_iexpr atom_names vals_list in
                 (dst, cond) :: acc)
              per_src
              []
          in
          let dests = List.sort_uniq compare dests in
          (i, chain dests))
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
  let fold_map = fold_map_for_node n in
  let inputs = List.map (fun v -> v.vname) n.inputs in
  let var_types =
    List.map (fun v -> (v.vname, v.vty)) (n.inputs @ n.locals @ n.outputs)
  in
  let atoms =
    collect_atoms_from_node n
    |> List.filter (fun a -> atom_to_iexpr ~inputs ~var_types ~fold_map a <> None)
    |> List.sort_uniq compare
  in
  let atom_exprs =
    List.filter_map
      (fun a ->
         match atom_to_iexpr ~inputs ~var_types ~fold_map a with
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
         match atom_to_iexpr ~inputs ~var_types ~fold_map a with
         | Some e -> SAssign (name, e)
         | None -> SSkip
      )
      atom_map
  in
  let atom_invariants =
    List.map (fun (name, e) -> Invariant (name, HNow e)) atom_named_exprs
  in
  let monitor_local = { vname = monitor_state_name; vty = TCustom monitor_state_type } in
  let user_assumes = List.map (replace_atoms_ltl atom_map) n.assumes in
  let user_guarantees = List.map (replace_atoms_ltl atom_map) n.guarantees in
  let invariants_mon = replace_atoms_invariants_mon atom_map n.invariants_mon in
  let spec =
    combine_contracts_for_monitor ~assumes:user_assumes ~guarantees:user_guarantees
    |> simplify_ltl
  in
  let valuations = all_valuations atom_names in
  let states, transitions = build_residual_graph atom_map valuations spec in
  let states, transitions =
    minimize_residual_graph valuations states transitions
  in
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
  let monitor_assumes, monitor_guarantees =
    let mon = monitor_state_name in
    let mk_state_formula i f =
      let cond =
        LAtom (FRel (HNow (IVar mon), REq, HNow (monitor_state_expr i)))
      in
      let f = simplify_ltl f in
      let inv = LG (LImp (cond, f)) in
      [inv]
    in
    let state_invs = List.concat (List.mapi mk_state_formula states) in
    let rec ltl_of_iexpr_now = function
      | ILitBool true -> LTrue
      | ILitBool false -> LFalse
      | IVar name ->
          let h = HNow (IVar name) in
          LAtom (FRel (h, REq, HNow (ILitBool true)))
      | IUn (Not, IVar name) ->
          let h = HNow (IVar name) in
          LAtom (FRel (h, REq, HNow (ILitBool false)))
      | IUn (Not, e) -> LNot (ltl_of_iexpr_now e)
      | IBin (And, a, b) -> LAnd (ltl_of_iexpr_now a, ltl_of_iexpr_now b)
      | IBin (Or, a, b) -> LOr (ltl_of_iexpr_now a, ltl_of_iexpr_now b)
      | _ -> LTrue
    in
    let incoming_prev =
      let by_dst = Hashtbl.create 16 in
      List.iter
        (fun (_i, vals, j) ->
           let prev = Hashtbl.find_opt by_dst j |> Option.value ~default:[] in
           Hashtbl.replace by_dst j (vals :: prev))
        transitions;
      Hashtbl.fold
        (fun j vals_list acc ->
           let cond =
             LAtom (FRel (HNow (IVar mon), REq, HNow (monitor_state_expr j)))
           in
           let guard_expr = valuations_to_iexpr atom_names vals_list in
           let guard = ltl_of_iexpr_now guard_expr in
           let inv = simplify_ltl (LG (LImp (cond, guard))) in
           inv :: acc)
        by_dst
        []
    in
    let incoming_prev = incoming_prev in
    (state_invs @ incoming_prev, incoming_prev)
  in
  let monitor_updates = monitor_update_stmts atom_names states transitions in
  let monitor_asserts = monitor_assert bad_idx in
  let trans =
    List.map
      (fun (t:transition) ->
         let t = replace_atoms_transition atom_map t in
         let body = t.body @ atom_assigns @ monitor_updates @ monitor_asserts in
         { t with body })
      n.trans
  in
  { n with
    locals = n.locals @ atom_locals @ [monitor_local];
    assumes = user_assumes @ monitor_assumes;
    guarantees = monitor_guarantees;
    invariants_mon = invariants_mon @ atom_invariants @ compat_invariants;
    trans;
  }
