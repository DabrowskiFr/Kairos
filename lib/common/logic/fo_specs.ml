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
open Ast_builders
open Generated_names
open Temporal_support
open Ast_pretty
open Fo_formula

let rec collect_atoms_ltl (f : ltl) (acc : fo_atom list) : fo_atom list =
  match f with
  | LTrue | LFalse -> acc
  | LAtom a -> if List.exists (( = ) a) acc then acc else a :: acc
  | LNot a | LX a | LG a -> collect_atoms_ltl a acc
  | LAnd (a, b) | LOr (a, b) | LImp (a, b) | LW (a, b) ->
      collect_atoms_ltl b (collect_atoms_ltl a acc)

and collect_atoms_fo (f : fo_atom) (acc : fo_atom list) : fo_atom list =
  if List.exists (( = ) f) acc then acc else f :: acc

let collect_atoms_from_node (n : Ast.node) : fo_atom list =
  let spec = Ast.specification_of_node n in
  let acc =
    List.fold_left
      (fun acc f -> collect_atoms_ltl f acc)
      [] (spec.spec_assumes @ spec.spec_guarantees)
  in
  List.fold_left (fun acc inv -> collect_atoms_ltl inv.formula acc) acc spec.spec_invariants_state_rel

let transition_fo (_t : Ast.transition) : ltl list = []

let conj_fo (fs : Fo_formula.t list) : Fo_formula.t option =
  match fs with
  | [] -> None
  | f :: rest -> Some (List.fold_left (fun acc x -> FAnd (acc, x)) f rest)

let conj_ltl (fs : ltl list) : ltl option =
  match fs with
  | [] -> None
  | f :: rest -> Some (List.fold_left (fun acc x -> LAnd (acc, x)) f rest)

let relop_to_binop (r : relop) : binop =
  match r with REq -> Eq | RNeq -> Neq | RLt -> Lt | RLe -> Le | RGt -> Gt | RGe -> Ge

type temporal_binding = {
  source_hexpr : Ast.hexpr;
  slot_names : Ast.ident list;
}

let temporal_bindings_of_pre_k_map ~(pre_k_map : (hexpr * Temporal_support.pre_k_info) list) :
    temporal_binding list =
  List.map
    (fun (source_hexpr, info) ->
      let slot_names =
        match source_hexpr with
        | HPreK (_, k) when k > 0 && k <= List.length info.Temporal_support.names -> [ List.nth info.Temporal_support.names (k - 1) ]
        | HPreK _ -> []
        | HNow _ -> info.Temporal_support.names
      in
      { source_hexpr; slot_names })
    pre_k_map

let latest_temporal_slot ~(temporal_bindings : temporal_binding list) (h : hexpr) : ident option =
  temporal_bindings
  |> List.find_map (fun binding ->
         if binding.source_hexpr = h then
           match List.rev binding.slot_names with
           | name :: _ -> Some name
           | [] -> None
         else None)

let hexpr_to_iexpr_with_temporal_bindings ~(inputs : ident list) ~(var_types : (ident * ty) list)
    ~(temporal_bindings : temporal_binding list) (h : hexpr) : iexpr option =
  let _ = (inputs, var_types) in
  match h with
  | HNow e -> Some e
  | HPreK _ as h -> begin
      match latest_temporal_slot ~temporal_bindings h with
      | Some name -> Some (mk_var name)
      | None -> None
    end

let hexpr_to_iexpr ~(inputs : ident list) ~(var_types : (ident * ty) list)
    ~(pre_k_map : (hexpr * Temporal_support.pre_k_info) list) (h : hexpr) : iexpr option =
  hexpr_to_iexpr_with_temporal_bindings ~inputs ~var_types
    ~temporal_bindings:(temporal_bindings_of_pre_k_map ~pre_k_map) h

let lower_hexpr_temporal_bindings ~(temporal_bindings : temporal_binding list) (h : hexpr) :
    hexpr option =
  match hexpr_to_iexpr_with_temporal_bindings ~inputs:[] ~var_types:[] ~temporal_bindings h with
  | Some e -> Some (HNow e)
  | None -> None

let lower_hexpr_pre_k ~(pre_k_map : (hexpr * Temporal_support.pre_k_info) list) (h : hexpr) : hexpr option =
  lower_hexpr_temporal_bindings ~temporal_bindings:(temporal_bindings_of_pre_k_map ~pre_k_map) h

let lower_fo_temporal_bindings ~(temporal_bindings : temporal_binding list) (f : fo_atom) : fo_atom option =
  match f with
  | FRel (h1, r, h2) -> begin
      match (lower_hexpr_temporal_bindings ~temporal_bindings h1, lower_hexpr_temporal_bindings ~temporal_bindings h2) with
      | Some h1', Some h2' -> Some (FRel (h1', r, h2'))
      | _ -> None
    end
  | FPred (id, hs) ->
      let rec lower_args acc = function
        | [] -> Some (List.rev acc)
        | h :: tl -> (
            match lower_hexpr_temporal_bindings ~temporal_bindings h with
            | None -> None
            | Some h' -> lower_args (h' :: acc) tl)
      in
      Option.map (fun hs' -> FPred (id, hs')) (lower_args [] hs)

let lower_fo_pre_k ~(pre_k_map : (hexpr * Temporal_support.pre_k_info) list) (f : fo_atom) : fo_atom option =
  lower_fo_temporal_bindings ~temporal_bindings:(temporal_bindings_of_pre_k_map ~pre_k_map) f

let rec lower_fo_formula_temporal_bindings ~(temporal_bindings : temporal_binding list)
    (f : Fo_formula.t) : Fo_formula.t option =
  match f with
  | Fo_formula.FTrue -> Some Fo_formula.FTrue
  | Fo_formula.FFalse -> Some Fo_formula.FFalse
  | Fo_formula.FAtom atom ->
      Option.map (fun atom' -> Fo_formula.FAtom atom')
        (lower_fo_temporal_bindings ~temporal_bindings atom)
  | Fo_formula.FNot a ->
      Option.map (fun a' -> Fo_formula.FNot a')
        (lower_fo_formula_temporal_bindings ~temporal_bindings a)
  | Fo_formula.FAnd (a, b) -> begin
      match
        ( lower_fo_formula_temporal_bindings ~temporal_bindings a,
          lower_fo_formula_temporal_bindings ~temporal_bindings b )
      with
      | Some a', Some b' -> Some (Fo_formula.FAnd (a', b'))
      | _ -> None
    end
  | Fo_formula.FOr (a, b) -> begin
      match
        ( lower_fo_formula_temporal_bindings ~temporal_bindings a,
          lower_fo_formula_temporal_bindings ~temporal_bindings b )
      with
      | Some a', Some b' -> Some (Fo_formula.FOr (a', b'))
      | _ -> None
    end
  | Fo_formula.FImp (a, b) -> begin
      match
        ( lower_fo_formula_temporal_bindings ~temporal_bindings a,
          lower_fo_formula_temporal_bindings ~temporal_bindings b )
      with
      | Some a', Some b' -> Some (Fo_formula.FImp (a', b'))
      | _ -> None
    end

let lower_fo_formula_pre_k ~(pre_k_map : (hexpr * Temporal_support.pre_k_info) list)
    (f : Fo_formula.t) : Fo_formula.t option =
  lower_fo_formula_temporal_bindings ~temporal_bindings:(temporal_bindings_of_pre_k_map ~pre_k_map) f

let rec lower_ltl_temporal_bindings ~(temporal_bindings : temporal_binding list) (f : ltl) :
    ltl option =
  match f with
  | LTrue | LFalse -> Some f
  | LAtom a -> Option.map (fun a' -> LAtom a') (lower_fo_temporal_bindings ~temporal_bindings a)
  | LNot a -> Option.map (fun a' -> LNot a') (lower_ltl_temporal_bindings ~temporal_bindings a)
  | LX a -> Option.map (fun a' -> LX a') (lower_ltl_temporal_bindings ~temporal_bindings a)
  | LG a -> Option.map (fun a' -> LG a') (lower_ltl_temporal_bindings ~temporal_bindings a)
  | LAnd (a, b) -> begin
      match
        (lower_ltl_temporal_bindings ~temporal_bindings a, lower_ltl_temporal_bindings ~temporal_bindings b)
      with
      | Some a', Some b' -> Some (LAnd (a', b'))
      | _ -> None
    end
  | LOr (a, b) -> begin
      match
        (lower_ltl_temporal_bindings ~temporal_bindings a, lower_ltl_temporal_bindings ~temporal_bindings b)
      with
      | Some a', Some b' -> Some (LOr (a', b'))
      | _ -> None
    end
  | LImp (a, b) -> begin
      match
        (lower_ltl_temporal_bindings ~temporal_bindings a, lower_ltl_temporal_bindings ~temporal_bindings b)
      with
      | Some a', Some b' -> Some (LImp (a', b'))
      | _ -> None
    end
  | LW (a, b) -> begin
      match
        (lower_ltl_temporal_bindings ~temporal_bindings a, lower_ltl_temporal_bindings ~temporal_bindings b)
      with
      | Some a', Some b' -> Some (LW (a', b'))
      | _ -> None
    end

let lower_ltl_pre_k ~(pre_k_map : (hexpr * Temporal_support.pre_k_info) list) (f : ltl) : ltl option =
  lower_ltl_temporal_bindings ~temporal_bindings:(temporal_bindings_of_pre_k_map ~pre_k_map) f

let infer_iexpr_type ~(var_types : (ident * ty) list) (e : iexpr) : ty option =
  let rec go = function
    | ILitBool _ -> Some TBool
    | ILitInt _ -> Some TInt
    | IVar x -> List.assoc_opt x var_types
    | IPar e -> go e.iexpr
    | IUn (Not, _) -> Some TBool
    | IUn (Neg, _) -> Some TInt
    | IBin (And, _, _) | IBin (Or, _, _) -> Some TBool
    | IBin (Eq, _, _) | IBin (Neq, _, _) -> Some TBool
    | IBin (Lt, _, _) | IBin (Le, _, _) | IBin (Gt, _, _) | IBin (Ge, _, _) -> Some TBool
    | IBin (Add, _, _) | IBin (Sub, _, _) | IBin (Mul, _, _) | IBin (Div, _, _) -> Some TInt
  in
  go e.iexpr

let mk_bool_eq (a : iexpr) (b : iexpr) : iexpr =
  mk_iexpr
    (IBin
       ( Or,
         mk_iexpr (IBin (And, a, b)),
         mk_iexpr (IBin (And, mk_iexpr (IUn (Not, a)), mk_iexpr (IUn (Not, b)))) ))

let mk_bool_neq (a : iexpr) (b : iexpr) : iexpr =
  mk_iexpr
    (IBin
       ( Or,
         mk_iexpr (IBin (And, a, mk_iexpr (IUn (Not, b)))),
         mk_iexpr (IBin (And, mk_iexpr (IUn (Not, a)), b)) ))

let atom_to_iexpr ~(inputs : ident list) ~(var_types : (ident * ty) list)
    ~(pre_k_map : (hexpr * Temporal_support.pre_k_info) list) (f : fo_atom) : iexpr option =
  match f with
  | FRel (h1, r, h2) -> begin
      match
        ( hexpr_to_iexpr ~inputs ~var_types ~pre_k_map h1,
          hexpr_to_iexpr ~inputs ~var_types ~pre_k_map h2 )
      with
      | Some e1, Some e2 ->
          let ty1 = infer_iexpr_type ~var_types e1 in
          let ty2 = infer_iexpr_type ~var_types e2 in
          begin match (ty1, ty2, r) with
          | Some TBool, Some TBool, REq -> Some (mk_bool_eq e1 e2)
          | Some TBool, Some TBool, RNeq -> Some (mk_bool_neq e1 e2)
          | _ -> Some (mk_iexpr (IBin (relop_to_binop r, e1, e2)))
          end
      | _ -> None
    end
  | FPred _ -> None

let atom_to_var_rel (name : ident) : fo_atom = FRel (HNow (mk_var name), REq, HNow (mk_bool true))

let rec iexpr_to_fo_with_atoms (atom_map : (ident * fo_atom) list) (e : iexpr) : Fo_formula.t =
  match e.iexpr with
  | ILitBool true -> FTrue
  | ILitBool false -> FFalse
  | ILitInt i -> FAtom (FRel (HNow (mk_int i), REq, HNow (mk_bool true)))
  | IVar v -> begin
      match List.assoc_opt v atom_map with
      | Some f -> FAtom f
      | None -> FAtom (FRel (HNow (mk_var v), REq, HNow (mk_bool true)))
    end
  | IPar e -> iexpr_to_fo_with_atoms atom_map e
  | IUn (Not, a) -> FNot (iexpr_to_fo_with_atoms atom_map a)
  | IBin (And, a, b) -> FAnd (iexpr_to_fo_with_atoms atom_map a, iexpr_to_fo_with_atoms atom_map b)
  | IBin (Or, a, b) -> FOr (iexpr_to_fo_with_atoms atom_map a, iexpr_to_fo_with_atoms atom_map b)
  | IBin (Eq, a, b) -> FAtom (FRel (HNow a, REq, HNow b))
  | IBin (Neq, a, b) -> FAtom (FRel (HNow a, RNeq, HNow b))
  | IBin (Lt, a, b) -> FAtom (FRel (HNow a, RLt, HNow b))
  | IBin (Le, a, b) -> FAtom (FRel (HNow a, RLe, HNow b))
  | IBin (Gt, a, b) -> FAtom (FRel (HNow a, RGt, HNow b))
  | IBin (Ge, a, b) -> FAtom (FRel (HNow a, RGe, HNow b))
  | IBin (_, a, b) -> FAtom (FRel (HNow (mk_iexpr (IBin (Eq, a, b))), REq, HNow (mk_bool true)))
  | IUn (_, a) -> FAtom (FRel (HNow (mk_iexpr (IUn (Not, a))), REq, HNow (mk_bool true)))

let rec fo_formula_of_non_temporal_ltl (f : ltl) : Fo_formula.t option =
  match f with
  | LTrue -> Some Fo_formula.FTrue
  | LFalse -> Some Fo_formula.FFalse
  | LAtom a -> Some (Fo_formula.FAtom a)
  | LNot a ->
      Option.map (fun a' -> Fo_formula.FNot a') (fo_formula_of_non_temporal_ltl a)
  | LAnd (a, b) -> begin
      match (fo_formula_of_non_temporal_ltl a, fo_formula_of_non_temporal_ltl b) with
      | Some a', Some b' -> Some (Fo_formula.FAnd (a', b'))
      | _ -> None
    end
  | LOr (a, b) -> begin
      match (fo_formula_of_non_temporal_ltl a, fo_formula_of_non_temporal_ltl b) with
      | Some a', Some b' -> Some (Fo_formula.FOr (a', b'))
      | _ -> None
    end
  | LImp (a, b) -> begin
      match (fo_formula_of_non_temporal_ltl a, fo_formula_of_non_temporal_ltl b) with
      | Some a', Some b' -> Some (Fo_formula.FImp (a', b'))
      | _ -> None
    end
  | LX _ | LG _ | LW _ -> None

let fo_formula_of_non_temporal_ltl_exn (f : ltl) : Fo_formula.t =
  match fo_formula_of_non_temporal_ltl f with
  | Some ff -> ff
  | None ->
      failwith
        (Printf.sprintf "fo_formula_of_non_temporal_ltl_exn: temporal operator in %s"
           (Ast_pretty.string_of_ltl f))

let rec replace_atoms_ltl (atom_map : (fo_atom * ident) list) (f : ltl) : ltl =
  match f with
  | LTrue | LFalse -> f
  | LAtom a -> LAtom (replace_atoms_fo atom_map a)
  | LNot a -> LNot (replace_atoms_ltl atom_map a)
  | LAnd (a, b) -> LAnd (replace_atoms_ltl atom_map a, replace_atoms_ltl atom_map b)
  | LOr (a, b) -> LOr (replace_atoms_ltl atom_map a, replace_atoms_ltl atom_map b)
  | LImp (a, b) -> LImp (replace_atoms_ltl atom_map a, replace_atoms_ltl atom_map b)
  | LX a -> LX (replace_atoms_ltl atom_map a)
  | LG a -> LG (replace_atoms_ltl atom_map a)
  | LW (a, b) -> LW (replace_atoms_ltl atom_map a, replace_atoms_ltl atom_map b)

and replace_atoms_fo (atom_map : (fo_atom * ident) list) (f : fo_atom) : fo_atom =
  match f with
  | FRel _ | FPred _ -> begin
      match List.assoc_opt f atom_map with Some name -> atom_to_var_rel name | None -> f
    end

let replace_atoms_invariants_state_rel (atom_map : (fo_atom * ident) list)
    (invs : invariant_state_rel list) : invariant_state_rel list =
  List.map (fun inv -> { inv with formula = replace_atoms_ltl atom_map inv.formula }) invs

let replace_atoms_transition (_atom_map : (fo_atom * ident) list) (t : Ast.transition) : Ast.transition =
  t

(* Fold-specific helpers removed. *)

let combine_contracts_for_monitor ~(assumes : ltl list) ~(guarantees : ltl list) : ltl =
  let rec mk_and = function [] -> LTrue | [ x ] -> x | x :: xs -> LAnd (x, mk_and xs) in
  let g = mk_and (List.rev guarantees) in
  let _ = assumes in
  (* Monitorization targets guarantees only.
     Assumptions stay as global proof hypotheses in backend contracts. *)
  match guarantees with [] -> LTrue | _ -> g
