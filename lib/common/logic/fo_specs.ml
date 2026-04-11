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
open Core_syntax
open Ast
open Ast_builders
open Temporal_support
open Logic_pretty
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

let conj_fo (fs : Fo_formula.t list) : Fo_formula.t option =
  match fs with
  | [] -> None
  | f :: rest -> Some (List.fold_left (fun acc x -> FAnd (acc, x)) f rest)


type temporal_binding = {
  source_hexpr : Core_syntax.hexpr;
  slot_names : Core_syntax.ident list;
}

let temporal_bindings_of_pre_k_map ~(pre_k_map : (hexpr * Temporal_support.pre_k_info) list) :
    temporal_binding list =
  List.map
    (fun (source_hexpr, info) ->
      let slot_names =
        match source_hexpr.hexpr with
        | HPreK (_, k) when k > 0 && k <= List.length info.Temporal_support.names ->
            [ List.nth info.Temporal_support.names (k - 1) ]
        | HPreK _ -> []
        | _ -> info.Temporal_support.names
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

let rec hexpr_to_iexpr_with_temporal_bindings ~(inputs : ident list) ~(var_types : (ident * ty) list)
    ~(temporal_bindings : temporal_binding list) (h : hexpr) : iexpr option =
  let _ = (inputs, var_types) in
  let loc = h.loc in
  match h.hexpr with
  | HLitInt n -> Some { iexpr = ILitInt n; loc }
  | HLitBool b -> Some { iexpr = ILitBool b; loc }
  | HVar v -> Some { iexpr = IVar v; loc }
  | HPreK _ -> begin
      match latest_temporal_slot ~temporal_bindings h with
      | Some name -> Some { iexpr = IVar name; loc }
      | None -> None
    end
  | HUn (op, inner) ->
      Option.map (fun e -> { iexpr = IUn (op, e); loc })
        (hexpr_to_iexpr_with_temporal_bindings ~inputs ~var_types ~temporal_bindings inner)
  | HArithBin (op, a, b) -> begin
      match
        ( hexpr_to_iexpr_with_temporal_bindings ~inputs ~var_types ~temporal_bindings a,
          hexpr_to_iexpr_with_temporal_bindings ~inputs ~var_types ~temporal_bindings b )
      with
      | Some a', Some b' -> Some { iexpr = IArithBin (op, a', b'); loc }
      | _ -> None
    end
  | HBoolBin (op, a, b) -> begin
      match
        ( hexpr_to_iexpr_with_temporal_bindings ~inputs ~var_types ~temporal_bindings a,
          hexpr_to_iexpr_with_temporal_bindings ~inputs ~var_types ~temporal_bindings b )
      with
      | Some a', Some b' ->
          Some { iexpr = IBoolBin (op, a', b'); loc }
      | _ -> None
    end
  | HCmp (op, a, b) -> begin
      match
        ( hexpr_to_iexpr_with_temporal_bindings ~inputs ~var_types ~temporal_bindings a,
          hexpr_to_iexpr_with_temporal_bindings ~inputs ~var_types ~temporal_bindings b )
      with
      | Some a', Some b' -> Some { iexpr = ICmp (op, a', b'); loc }
      | _ -> None
    end

let hexpr_to_iexpr ~(inputs : ident list) ~(var_types : (ident * ty) list)
    ~(pre_k_map : (hexpr * Temporal_support.pre_k_info) list) (h : hexpr) : iexpr option =
  hexpr_to_iexpr_with_temporal_bindings ~inputs ~var_types
    ~temporal_bindings:(temporal_bindings_of_pre_k_map ~pre_k_map) h

let rec lower_hexpr_temporal_bindings ~(temporal_bindings : temporal_binding list) (h : hexpr) :
    hexpr option =
  let loc = h.loc in
  match h.hexpr with
  | HLitInt _ | HLitBool _ | HVar _ -> Some h
  | HPreK _ -> begin
      match latest_temporal_slot ~temporal_bindings h with
      | Some name -> Some { hexpr = HVar name; loc }
      | None -> None
    end
  | HUn (op, inner) ->
      Option.map (fun inner' -> { hexpr = HUn (op, inner'); loc })
        (lower_hexpr_temporal_bindings ~temporal_bindings inner)
  | HArithBin (op, a, b) -> begin
      match
        ( lower_hexpr_temporal_bindings ~temporal_bindings a,
          lower_hexpr_temporal_bindings ~temporal_bindings b )
      with
      | Some a', Some b' -> Some { hexpr = HArithBin (op, a', b'); loc }
      | _ -> None
    end
  | HBoolBin (op, a, b) -> begin
      match
        ( lower_hexpr_temporal_bindings ~temporal_bindings a,
          lower_hexpr_temporal_bindings ~temporal_bindings b )
      with
      | Some a', Some b' -> Some { hexpr = HBoolBin (op, a', b'); loc }
      | _ -> None
    end
  | HCmp (op, a, b) -> begin
      match
        ( lower_hexpr_temporal_bindings ~temporal_bindings a,
          lower_hexpr_temporal_bindings ~temporal_bindings b )
      with
      | Some a', Some b' -> Some { hexpr = HCmp (op, a', b'); loc }
      | _ -> None
    end

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


let infer_iexpr_type ~(var_types : (ident * ty) list) (e : iexpr) : ty option =
  let rec go = function
    | ILitBool _ -> Some TBool
    | ILitInt _ -> Some TInt
    | IVar x -> List.assoc_opt x var_types
    | IUn (Not, _) -> Some TBool
    | IUn (Neg, _) -> Some TInt
    | IBoolBin (_, _, _) -> Some TBool
    | ICmp (_, _, _) -> Some TBool
    | IArithBin (_, _, _) -> Some TInt
  in
  go e.iexpr

let mk_bool_eq (a : iexpr) (b : iexpr) : iexpr =
  mk_iexpr
    (IBoolBin
       ( Or,
         mk_iexpr (IBoolBin (And, a, b)),
         mk_iexpr (IBoolBin (And, mk_iexpr (IUn (Not, a)), mk_iexpr (IUn (Not, b)))) ))

let mk_bool_neq (a : iexpr) (b : iexpr) : iexpr =
  mk_iexpr
    (IBoolBin
       ( Or,
         mk_iexpr (IBoolBin (And, a, mk_iexpr (IUn (Not, b)))),
         mk_iexpr (IBoolBin (And, mk_iexpr (IUn (Not, a)), b)) ))

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
          | _ -> Some (mk_iexpr (ICmp (r, e1, e2)))
          end
      | _ -> None
    end
  | FPred _ -> None

let atom_to_var_rel (name : ident) : fo_atom = FRel (mk_hvar name, REq, mk_hbool true)

let rec iexpr_to_fo_with_atoms (atom_map : (ident * fo_atom) list) (e : iexpr) : Fo_formula.t =
  match e.iexpr with
  | ILitBool true -> FTrue
  | ILitBool false -> FFalse
  | ILitInt i -> FAtom (FRel (mk_hint i, REq, mk_hbool true))
  | IVar v -> begin
      match List.assoc_opt v atom_map with
      | Some f -> FAtom f
      | None -> FAtom (FRel (mk_hvar v, REq, mk_hbool true))
    end
  | IUn (Not, a) -> FNot (iexpr_to_fo_with_atoms atom_map a)
  | IBoolBin (And, a, b) ->
      FAnd (iexpr_to_fo_with_atoms atom_map a, iexpr_to_fo_with_atoms atom_map b)
  | IBoolBin (Or, a, b) ->
      FOr (iexpr_to_fo_with_atoms atom_map a, iexpr_to_fo_with_atoms atom_map b)
  | ICmp (REq, a, b) -> FAtom (FRel (hexpr_of_iexpr a, REq, hexpr_of_iexpr b))
  | ICmp (RNeq, a, b) -> FAtom (FRel (hexpr_of_iexpr a, RNeq, hexpr_of_iexpr b))
  | ICmp (RLt, a, b) -> FAtom (FRel (hexpr_of_iexpr a, RLt, hexpr_of_iexpr b))
  | ICmp (RLe, a, b) -> FAtom (FRel (hexpr_of_iexpr a, RLe, hexpr_of_iexpr b))
  | ICmp (RGt, a, b) -> FAtom (FRel (hexpr_of_iexpr a, RGt, hexpr_of_iexpr b))
  | ICmp (RGe, a, b) -> FAtom (FRel (hexpr_of_iexpr a, RGe, hexpr_of_iexpr b))
  | IArithBin (_, _, _) | IUn (Neg, _) ->
      FAtom (FRel (hexpr_of_iexpr e, REq, mk_hbool true))



(* Fold-specific helpers removed. *)

let combine_contracts_for_monitor ~(assumes : ltl list) ~(guarantees : ltl list) : ltl =
  let rec mk_and = function [] -> LTrue | [ x ] -> x | x :: xs -> LAnd (x, mk_and xs) in
  let g = mk_and (List.rev guarantees) in
  let _ = assumes in
  (* Monitorization targets guarantees only.
     Assumptions stay as global proof hypotheses in backend contracts. *)
  match guarantees with [] -> LTrue | _ -> g
