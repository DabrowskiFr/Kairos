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
open Pipeline_cost_report_common

let rec expr_size (e : expr) =
  match e.expr with
  | ELitInt _ | ELitBool _ | ELitEnum _ | EVar _ -> 1
  | EFunCall (_, args) -> 1 + sum_int (List.map expr_size args)
  | EUn (_, inner) -> 1 + expr_size inner
  | EBin (_, a, b) | ECmp (_, a, b) -> 1 + expr_size a + expr_size b

let rec hexpr_size (h : hexpr) =
  match h.hexpr with
  | HLitInt _ | HLitBool _ | HLitEnum _ | HVar _ | HPreK _ -> 1
  | HPred (_, args) | HFunCall (_, args) -> 1 + sum_int (List.map hexpr_size args)
  | HUn (_, inner) -> 1 + hexpr_size inner
  | HBin (_, a, b) | HCmp (_, a, b) -> 1 + hexpr_size a + hexpr_size b

let rec stmt_size (s : stmt) =
  match s.stmt with
  | SAssign (_, e) -> 1 + expr_size e
  | SAssert formula -> 1 + hexpr_size formula
  | SIf (guard, then_branch, else_branch) ->
      1 + expr_size guard + sum_int (List.map stmt_size then_branch)
      + sum_int (List.map stmt_size else_branch)
  | SWhile (guard, invariants, variant, body) ->
      1 + expr_size guard + sum_int (List.map hexpr_size invariants)
      + (match variant with None -> 0 | Some variant -> expr_size variant)
      + sum_int (List.map stmt_size body)
  | SMatch (scrutinee, branches, default_branch) ->
      1 + expr_size scrutinee
      + sum_int
          (List.map
             (fun (_, body) -> sum_int (List.map stmt_size body))
             branches)
      + sum_int (List.map stmt_size default_branch)
  | SSkip -> 1
  | SCall (_, args, outs) -> 1 + List.length outs + sum_int (List.map expr_size args)

let rec hexpr_max_pre_depth (h : hexpr) =
  match h.hexpr with
  | HLitInt _ | HLitBool _ | HLitEnum _ | HVar _ -> 0
  | HPreK (_, k) -> k
  | HPred (_, args) | HFunCall (_, args) -> max_int (List.map hexpr_max_pre_depth args)
  | HUn (_, inner) -> hexpr_max_pre_depth inner
  | HBin (_, a, b) | HCmp (_, a, b) ->
      max (hexpr_max_pre_depth a) (hexpr_max_pre_depth b)

let rec hexpr_free_variables (h : hexpr) =
  match h.hexpr with
  | HLitInt _ | HLitBool _ | HLitEnum _ -> StringSet.empty
  | HVar v | HPreK (v, _) -> StringSet.singleton v
  | HPred (_, args) | HFunCall (_, args) ->
      List.fold_left
        (fun acc h -> StringSet.union acc (hexpr_free_variables h))
        StringSet.empty args
  | HUn (_, inner) -> hexpr_free_variables inner
  | HBin (_, a, b) | HCmp (_, a, b) ->
      StringSet.union (hexpr_free_variables a) (hexpr_free_variables b)

let rec ltl_size = function
  | LTrue | LFalse -> 1
  | LAtom (a, _, b) -> 1 + hexpr_size a + hexpr_size b
  | LNot a | LX a | LG a -> 1 + ltl_size a
  | LAnd (a, b) | LOr (a, b) | LImp (a, b) | LW (a, b) ->
      1 + ltl_size a + ltl_size b

let rec ltl_temporal_depth = function
  | LTrue | LFalse | LAtom _ -> 0
  | LNot a -> ltl_temporal_depth a
  | LX a | LG a -> 1 + ltl_temporal_depth a
  | LAnd (a, b) | LOr (a, b) | LImp (a, b) ->
      max (ltl_temporal_depth a) (ltl_temporal_depth b)
  | LW (a, b) -> 1 + max (ltl_temporal_depth a) (ltl_temporal_depth b)

let rec ltl_max_pre_depth = function
  | LTrue | LFalse -> 0
  | LAtom (a, _, b) -> max (hexpr_max_pre_depth a) (hexpr_max_pre_depth b)
  | LNot a | LX a | LG a -> ltl_max_pre_depth a
  | LAnd (a, b) | LOr (a, b) | LImp (a, b) | LW (a, b) ->
      max (ltl_max_pre_depth a) (ltl_max_pre_depth b)
