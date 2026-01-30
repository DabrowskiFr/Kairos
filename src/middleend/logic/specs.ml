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

let rec collect_atoms_ltl (f:ltl) (acc:fo list) : fo list =
  match f with
  | LTrue | LFalse -> acc
  | LAtom a -> collect_atoms_fo a acc
  | LNot a | LX a | LG a -> collect_atoms_ltl a acc
  | LAnd (a,b) | LOr (a,b) | LImp (a,b) ->
      collect_atoms_ltl b (collect_atoms_ltl a acc)

and collect_atoms_fo (f:fo) (acc:fo list) : fo list =
  let add a acc = if List.exists ((=) a) acc then acc else a :: acc in
  match f with
  | FTrue | FFalse -> acc
  | FRel _ | FPred _ -> add f acc
  | FNot a -> collect_atoms_fo a acc
  | FAnd (a,b) | FOr (a,b) | FImp (a,b) ->
      collect_atoms_fo b (collect_atoms_fo a acc)

let collect_atoms_from_node (n:node) : fo list =
  let acc = List.fold_left (fun acc f -> collect_atoms_ltl f acc) [] (n.assumes @ n.guarantees) in
  List.fold_left
    (fun acc inv ->
       match inv with
       | Invariant (_id, _h) -> acc
       | InvariantStateRel (_is_eq, _st, f) -> collect_atoms_fo f acc)
    acc
    n.invariants_mon

let transition_fo (t:transition) : fo list =
  t.requires @ t.ensures @ t.lemmas

let relop_to_binop (r:relop) : binop =
  match r with
  | REq -> Eq
  | RNeq -> Neq
  | RLt -> Lt
  | RLe -> Le
  | RGt -> Gt
  | RGe -> Ge

let fold_var_of_hexpr (fold_map:(hexpr * ident) list) (h:hexpr)
  : ident option =
  List.find_map (fun (h', name) -> if h = h' then Some name else None) fold_map

let pre_k_var_of_hexpr ~(pre_k_map:(hexpr * Support.pre_k_info) list)
  (h:hexpr) : ident option =
  match List.find_opt (fun (h', _) -> h' = h) pre_k_map with
  | None -> None
  | Some (_h, info) ->
      let names = info.Support.names in
      if names = [] then None else Some (List.nth names (List.length names - 1))

let hexpr_to_iexpr ~(inputs:ident list) ~(fold_map:(hexpr * ident) list)
  ~(var_types:(ident * ty) list)
  ~(pre_k_map:(hexpr * Support.pre_k_info) list) (h:hexpr) : iexpr option =
  match h with
  | HNow e -> Some e
  | HFold _ as h ->
      begin match fold_var_of_hexpr fold_map h with
      | Some name -> Some (IVar name)
      | None -> None
      end
  | HPre (IVar x) ->
      if List.mem x inputs || List.mem_assoc x var_types then
        Some (IVar (Support.pre_input_old_name x))
      else
        None
  | HPreK _ as h ->
      begin match pre_k_var_of_hexpr ~pre_k_map h with
      | Some name -> Some (IVar name)
      | None -> None
      end
  | _ -> None

let infer_iexpr_type ~(var_types:(ident * ty) list) (e:iexpr) : ty option =
  let rec go = function
    | ILitBool _ -> Some TBool
    | ILitInt _ -> Some TInt
    | IVar x -> List.assoc_opt x var_types
    | IPar e -> go e
    | IUn (Not, _) -> Some TBool
    | IUn (Neg, _) -> Some TInt
    | IBin (And, _, _) | IBin (Or, _, _) -> Some TBool
    | IBin (Eq, _, _) | IBin (Neq, _, _) -> Some TBool
    | IBin (Lt, _, _) | IBin (Le, _, _) | IBin (Gt, _, _) | IBin (Ge, _, _) -> Some TBool
    | IBin (Add, _, _) | IBin (Sub, _, _) | IBin (Mul, _, _) | IBin (Div, _, _) -> Some TInt
  in
  go e

let mk_bool_eq (a:iexpr) (b:iexpr) : iexpr =
  IBin (Or,
        IBin (And, a, b),
        IBin (And, IUn (Not, a), IUn (Not, b)))

let mk_bool_neq (a:iexpr) (b:iexpr) : iexpr =
  IBin (Or,
        IBin (And, a, IUn (Not, b)),
        IBin (And, IUn (Not, a), b))

let atom_to_iexpr ~(inputs:ident list) ~(var_types:(ident * ty) list)
  ~(fold_map:(hexpr * ident) list) ~(pre_k_map:(hexpr * Support.pre_k_info) list)
  (f:fo) : iexpr option =
  match f with
  | FRel (h1, r, h2) ->
      begin match hexpr_to_iexpr ~inputs ~fold_map ~var_types ~pre_k_map h1,
                  hexpr_to_iexpr ~inputs ~fold_map ~var_types ~pre_k_map h2 with
      | Some e1, Some e2 ->
          let ty1 = infer_iexpr_type ~var_types e1 in
          let ty2 = infer_iexpr_type ~var_types e2 in
          begin match ty1, ty2, r with
          | Some TBool, Some TBool, REq -> Some (mk_bool_eq e1 e2)
          | Some TBool, Some TBool, RNeq -> Some (mk_bool_neq e1 e2)
          | _ -> Some (IBin (relop_to_binop r, e1, e2))
          end
      | _ -> None
      end
  | FPred _ -> None
  | FTrue | FFalse | FNot _ | FAnd _ | FOr _ | FImp _ -> None

let atom_to_var_rel (name:ident) : fo =
  FRel (HNow (IVar name), REq, HNow (ILitBool true))

let rec replace_atoms_ltl (atom_map:(fo * ident) list) (f:ltl) : ltl =
  match f with
  | LTrue | LFalse -> f
  | LAtom a -> LAtom (replace_atoms_fo atom_map a)
  | LNot a -> LNot (replace_atoms_ltl atom_map a)
  | LAnd (a,b) -> LAnd (replace_atoms_ltl atom_map a, replace_atoms_ltl atom_map b)
  | LOr (a,b) -> LOr (replace_atoms_ltl atom_map a, replace_atoms_ltl atom_map b)
  | LImp (a,b) -> LImp (replace_atoms_ltl atom_map a, replace_atoms_ltl atom_map b)
  | LX a -> LX (replace_atoms_ltl atom_map a)
  | LG a -> LG (replace_atoms_ltl atom_map a)

and replace_atoms_fo (atom_map:(fo * ident) list) (f:fo) : fo =
  match f with
  | FTrue | FFalse -> f
  | FRel _ | FPred _ ->
      begin match List.assoc_opt f atom_map with
      | Some name -> atom_to_var_rel name
      | None -> f
      end
  | FNot a -> FNot (replace_atoms_fo atom_map a)
  | FAnd (a,b) -> FAnd (replace_atoms_fo atom_map a, replace_atoms_fo atom_map b)
  | FOr (a,b) -> FOr (replace_atoms_fo atom_map a, replace_atoms_fo atom_map b)
  | FImp (a,b) -> FImp (replace_atoms_fo atom_map a, replace_atoms_fo atom_map b)

let replace_atoms_invariants_mon (atom_map:(fo * ident) list)
  (invs:invariant_mon list) : invariant_mon list =
  List.map
    (function
      | Invariant (id, h) -> Invariant (id, h)
      | InvariantStateRel (is_eq, st, f) ->
          InvariantStateRel (is_eq, st, replace_atoms_fo atom_map f))
    invs

let replace_atoms_transition (atom_map:(fo * ident) list) (t:transition)
  : transition =
  let replace_fo_list = List.map (replace_atoms_fo atom_map) in
  { t with
    requires = replace_fo_list t.requires;
    ensures = replace_fo_list t.ensures;
    lemmas = replace_fo_list t.lemmas;
  }

let fold_map_for_node (n:node) : (hexpr * ident) list =
  let folds : Support.fold_info list =
    Collect.collect_folds_from_specs
      ~fo:[]
      ~ltl:(n.assumes @ n.guarantees)
      ~invariants_mon:n.invariants_mon
  in
  List.map (fun (fi:Support.fold_info) -> (fi.h, fi.acc)) folds

let rec fold_vars_in_iexpr (acc:ident list) (e:iexpr) : ident list =
  match e with
  | IVar v -> if List.mem v acc then acc else v :: acc
  | ILitInt _ | ILitBool _ -> acc
  | IPar e -> fold_vars_in_iexpr acc e
  | IUn (_, e) -> fold_vars_in_iexpr acc e
  | IBin (_, a, b) -> fold_vars_in_iexpr (fold_vars_in_iexpr acc a) b

let fold_origin_suffix_for_expr (fold_map:(hexpr * ident) list) (e:iexpr)
  : string =
  let vars = fold_vars_in_iexpr [] e in
  let origins =
    List.filter_map
      (fun v ->
         match List.find_opt (fun (_h, acc) -> acc = v) fold_map with
         | None -> None
         | Some (h, _) -> Some (v, h))
      vars
  in
  match origins with
  | [] -> ""
  | _ ->
      let parts =
        List.map
          (fun (v, h) -> v ^ " = " ^ Support.string_of_hexpr h)
          origins
      in
      " (" ^ String.concat ", " parts ^ ")"

let combine_contracts_for_monitor ~(assumes:ltl list) ~(guarantees:ltl list)
  : ltl =
  let rec mk_and = function
    | [] -> LTrue
    | [x] -> x
    | x :: xs -> LAnd (x, mk_and xs)
  in
  let a = mk_and (List.rev assumes) in
  let g = mk_and (List.rev guarantees) in
  match assumes, guarantees with
  | [], [] -> LTrue
  | [], _ -> g
  | _ , [] -> LImp (a, LTrue)
  | _ -> LImp (a, g)
