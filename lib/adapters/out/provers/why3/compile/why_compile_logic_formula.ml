(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frederic Dabrowski
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

module StringSet = Why_compile_ptree_helpers.StringSet

let balance_boolean_hexpr (formula : Core_syntax.hexpr) : Core_syntax.hexpr =
  let build_balanced op formulas =
    match formulas with
    | [] -> invalid_arg "balance_boolean_hexpr: empty boolean formula list"
    | [ formula ] -> formula
    | _ ->
        let arr = Array.of_list formulas in
        let rec build lo hi =
          if hi - lo = 1 then arr.(lo)
          else
            let mid = lo + ((hi - lo) / 2) in
            Core_syntax_builders.mk_hexpr (HBin (op, build lo mid, build mid hi))
        in
        build 0 (Array.length arr)
  in
  let rec flatten op acc h =
    match h.hexpr with
    | HBin (op', a, b) when op = op' -> flatten op (flatten op acc b) a
    | _ -> h :: acc
  in
  let rec normalize h =
    match h.hexpr with
    | HLitInt _ | HLitBool _ | HLitEnum _ | HVar _ | HPreK _ -> h
    | HUn (op, inner) ->
        Core_syntax_builders.with_hexpr_desc h (HUn (op, normalize inner))
    | HPred (id, hs) ->
        Core_syntax_builders.with_hexpr_desc h
          (HPred (id, List.map normalize hs))
    | HFunCall (fn, hs) ->
        Core_syntax_builders.with_hexpr_desc h
          (HFunCall (fn, List.map normalize hs))
    | HBin ((And | Or as op), _, _) ->
        flatten op [] h |> List.rev |> List.map normalize |> build_balanced op
    | HBin (op, a, b) ->
        Core_syntax_builders.with_hexpr_desc h
          (HBin (op, normalize a, normalize b))
    | HCmp (op, a, b) ->
        Core_syntax_builders.with_hexpr_desc h
          (HCmp (op, normalize a, normalize b))
  in
  normalize formula

let rec hexpr_size (h : Core_syntax.hexpr) : int =
  match h.hexpr with
  | HLitInt _ | HLitBool _ | HLitEnum _ | HVar _ | HPreK _ -> 1
  | HUn (_, inner) -> 1 + hexpr_size inner
  | HPred (_, hs) | HFunCall (_, hs) ->
      1 + List.fold_left (fun acc h -> acc + hexpr_size h) 0 hs
  | HBin (_, a, b) | HCmp (_, a, b) -> 1 + hexpr_size a + hexpr_size b

let rec vars_of_hexpr (acc : StringSet.t) (h : Core_syntax.hexpr) : StringSet.t =
  match h.hexpr with
  | HLitInt _ | HLitBool _ | HLitEnum _ -> acc
  | HVar name | HPreK (name, _) -> StringSet.add name acc
  | HUn (_, inner) -> vars_of_hexpr acc inner
  | HPred (_, hs) | HFunCall (_, hs) -> List.fold_left vars_of_hexpr acc hs
  | HBin (_, a, b) | HCmp (_, a, b) -> vars_of_hexpr (vars_of_hexpr acc a) b
