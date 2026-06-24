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

module Abs = Ir
module StringSet = Set.Make (String)

let dedup_summary_formulas (xs : Abs.summary_formula list) :
    Abs.summary_formula list =
  List.sort_uniq
    (fun (a : Abs.summary_formula) (b : Abs.summary_formula) ->
      Int.compare a.meta.oid b.meta.oid)
    xs

let dedup_summary_formulas_by_logic (xs : Abs.summary_formula list) :
    Abs.summary_formula list =
  List.fold_left
    (fun acc (x : Abs.summary_formula) ->
      if List.exists (fun (y : Abs.summary_formula) -> y.logic = x.logic) acc
      then acc
      else acc @ [ x ])
    [] xs

let rec vars_of_expr (acc : StringSet.t) (e : expr) : StringSet.t =
  match e.expr with
  | EVar name -> StringSet.add name acc
  | ELitInt _ | ELitBool _ | ELitEnum _ -> acc
  | EFunCall (_, args) -> List.fold_left vars_of_expr acc args
  | EUn (_, inner) -> vars_of_expr acc inner
  | EBin (_, a, b) | ECmp (_, a, b) -> vars_of_expr (vars_of_expr acc a) b

let rec vars_of_hexpr (acc : StringSet.t) (h : hexpr) : StringSet.t =
  match h.hexpr with
  | HLitInt _ | HLitBool _ | HLitEnum _ -> acc
  | HVar name | HPreK (name, _) -> StringSet.add name acc
  | HPred (_, hs) -> List.fold_left vars_of_hexpr acc hs
  | HFunCall (_, hs) -> List.fold_left vars_of_hexpr acc hs
  | HUn (_, inner) -> vars_of_hexpr acc inner
  | HBin (_, a, b) | HCmp (_, a, b) ->
      vars_of_hexpr (vars_of_hexpr acc a) b

let vars_of_summary_formulas (formulas : Abs.summary_formula list) :
    StringSet.t =
  List.fold_left
    (fun acc (f : Abs.summary_formula) -> vars_of_hexpr acc f.logic)
    StringSet.empty formulas

let rec vars_of_stmt (acc : StringSet.t) (s : stmt) : StringSet.t =
  match s.stmt with
  | SAssign (_name, expr) -> vars_of_expr acc expr
  | SAssert formula -> vars_of_hexpr acc formula
  | SIf (cond, then_branch, else_branch) ->
      let acc = vars_of_expr acc cond in
      let acc = List.fold_left vars_of_stmt acc then_branch in
      List.fold_left vars_of_stmt acc else_branch
  | SWhile (cond, invariants, variant, body) ->
      let acc = vars_of_expr acc cond in
      let acc = List.fold_left vars_of_hexpr acc invariants in
      let acc =
        Option.fold ~none:acc ~some:(fun e -> vars_of_expr acc e) variant
      in
      List.fold_left vars_of_stmt acc body
  | SMatch (scrutinee, branches, default_branch) ->
      let acc = vars_of_expr acc scrutinee in
      let acc =
        List.fold_left
          (fun acc (_ctor, body) -> List.fold_left vars_of_stmt acc body)
          acc branches
      in
      List.fold_left vars_of_stmt acc default_branch
  | SSkip | SCall _ -> acc

let rec split_top_level_or (f : Core_syntax.hexpr) : Core_syntax.hexpr list =
  match f.hexpr with
  | HBin (Or, a, b) -> split_top_level_or a @ split_top_level_or b
  | _ -> [ f ]

let disj_summary_formulas (formulas : Abs.summary_formula list) :
    Abs.summary_formula option =
  match dedup_summary_formulas_by_logic formulas with
  | [] -> None
  | f :: rest ->
      let logic =
        rest
        |> List.fold_left
             (fun acc (item : Abs.summary_formula) ->
               Core_syntax_builders.mk_hor acc item.logic)
             f.logic
        |> Core_fo_simplifier.simplify
      in
      Some (Ir_formula.make logic)

let rec slice_stmt (needed_after : StringSet.t) (s : stmt) :
    stmt option * StringSet.t =
  match s.stmt with
  | SAssign (name, expr) ->
      if StringSet.mem name needed_after then
        let needed_before =
          needed_after |> StringSet.remove name |> fun acc ->
          vars_of_expr acc expr
        in
        (Some s, needed_before)
      else (None, needed_after)
  | SAssert formula -> (Some s, vars_of_hexpr needed_after formula)
  | SIf (cond, then_branch, else_branch) ->
      let then_branch', then_needed = slice_stmts needed_after then_branch in
      let else_branch', else_needed = slice_stmts needed_after else_branch in
      if then_branch' = [] && else_branch' = [] then (None, needed_after)
      else
        let needed_before =
          StringSet.union then_needed else_needed |> fun acc ->
          vars_of_expr acc cond
        in
        ( Some { s with stmt = SIf (cond, then_branch', else_branch') },
          needed_before )
  | SWhile _ -> (Some s, vars_of_stmt needed_after s)
  | SMatch (scrutinee, branches, default_branch) ->
      let sliced_branches, branch_needed =
        List.fold_right
          (fun (ctor, body) (branches_acc, needed_acc) ->
            let body', body_needed = slice_stmts needed_after body in
            ((ctor, body') :: branches_acc, StringSet.union needed_acc body_needed))
          branches ([], StringSet.empty)
      in
      let default_branch', default_needed =
        slice_stmts needed_after default_branch
      in
      let has_body =
        default_branch' <> []
        || List.exists (fun (_, body) -> body <> []) sliced_branches
      in
      if not has_body then (None, needed_after)
      else
        let needed_before =
          StringSet.union branch_needed default_needed |> fun acc ->
          vars_of_expr acc scrutinee
        in
        ( Some
            {
              s with
              stmt = SMatch (scrutinee, sliced_branches, default_branch');
            },
          needed_before )
  | SSkip -> (None, needed_after)
  | SCall _ -> (Some s, needed_after)

and slice_stmts (needed_after : StringSet.t) (stmts : stmt list) :
    stmt list * StringSet.t =
  List.fold_left
    (fun (kept, needed) stmt ->
      let kept_stmt, needed_before = slice_stmt needed stmt in
      let kept =
        match kept_stmt with None -> kept | Some stmt -> stmt :: kept
      in
      (kept, needed_before))
    ([], needed_after) (List.rev stmts)

let slice_body_for_formulas (body : stmt list)
    (formulas : Abs.summary_formula list) : stmt list =
  let needed = vars_of_summary_formulas formulas in
  fst (slice_stmts needed body)
