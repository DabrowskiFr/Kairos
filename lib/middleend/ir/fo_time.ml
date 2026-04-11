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
open Ast
open Ast_builders

let shift_hexpr_forward ~(is_input : ident -> bool) (h : hexpr) : hexpr =
  let rec go (h : hexpr) =
    match h.hexpr with
    | HLitInt _ | HLitBool _ -> h
    | HVar v -> if is_input v then mk_hpre_k v 1 else h
    | HPreK (v, k) -> mk_hpre_k v (k + 1)
    | HUn (op, inner) -> with_hexpr_desc h (HUn (op, go inner))
    | HArithBin (op, a, b) -> with_hexpr_desc h (HArithBin (op, go a, go b))
    | HBoolBin (op, a, b) -> with_hexpr_desc h (HBoolBin (op, go a, go b))
    | HCmp (op, a, b) -> with_hexpr_desc h (HCmp (op, go a, go b))
  in
  go h

let shift_hexpr_backward ~(is_input : ident -> bool) (h : hexpr) : hexpr =
  let rec go (h : hexpr) =
    match h.hexpr with
    | HLitInt _ | HLitBool _ -> h
    | HVar v ->
        if is_input v then
          failwith
            (Printf.sprintf
               "shift_hexpr_backward: cannot backward-shift current input %s; \
                current inputs have no predecessor-time counterpart"
               v);
        h
    | HPreK (v, k) -> if k <= 1 then mk_hvar v else mk_hpre_k v (k - 1)
    | HUn (op, inner) -> with_hexpr_desc h (HUn (op, go inner))
    | HArithBin (op, a, b) -> with_hexpr_desc h (HArithBin (op, go a, go b))
    | HBoolBin (op, a, b) -> with_hexpr_desc h (HBoolBin (op, go a, go b))
    | HCmp (op, a, b) -> with_hexpr_desc h (HCmp (op, go a, go b))
  in
  go h

let shift_fo_forward_inputs ~(is_input : ident -> bool) (f : fo_atom) : fo_atom =
  match f with
  | FRel (h1, r, h2) -> FRel (shift_hexpr_forward ~is_input h1, r, shift_hexpr_forward ~is_input h2)
  | FPred (id, hs) -> FPred (id, List.map (shift_hexpr_forward ~is_input) hs)

let shift_fo_backward_inputs ~(is_input : ident -> bool) (f : fo_atom) : fo_atom =
  match f with
  | FRel (h1, r, h2) ->
      FRel (shift_hexpr_backward ~is_input h1, r, shift_hexpr_backward ~is_input h2)
  | FPred (id, hs) -> FPred (id, List.map (shift_hexpr_backward ~is_input) hs)

let rec shift_formula_forward_inputs ~(is_input : ident -> bool) (f : Fo_formula.t) :
    Fo_formula.t =
  let open Fo_formula in
  match f with
  | FTrue | FFalse -> f
  | FAtom a -> FAtom (shift_fo_forward_inputs ~is_input a)
  | FNot a -> FNot (shift_formula_forward_inputs ~is_input a)
  | FAnd (a, b) ->
      FAnd (shift_formula_forward_inputs ~is_input a, shift_formula_forward_inputs ~is_input b)
  | FOr (a, b) ->
      FOr (shift_formula_forward_inputs ~is_input a, shift_formula_forward_inputs ~is_input b)
  | FImp (a, b) ->
      FImp (shift_formula_forward_inputs ~is_input a, shift_formula_forward_inputs ~is_input b)

let rec shift_formula_backward_inputs ~(is_input : ident -> bool) (f : Fo_formula.t) :
    Fo_formula.t =
  let open Fo_formula in
  match f with
  | FTrue | FFalse -> f
  | FAtom a -> FAtom (shift_fo_backward_inputs ~is_input a)
  | FNot a -> FNot (shift_formula_backward_inputs ~is_input a)
  | FAnd (a, b) ->
      FAnd (shift_formula_backward_inputs ~is_input a, shift_formula_backward_inputs ~is_input b)
  | FOr (a, b) ->
      FOr (shift_formula_backward_inputs ~is_input a, shift_formula_backward_inputs ~is_input b)
  | FImp (a, b) ->
      FImp (shift_formula_backward_inputs ~is_input a, shift_formula_backward_inputs ~is_input b)

let shift_hexpr_forward_all (h : hexpr) : hexpr =
  let rec go (h : hexpr) =
    match h.hexpr with
    | HLitInt _ | HLitBool _ -> h
    | HVar v -> mk_hpre_k v 1
    | HPreK (v, k) -> mk_hpre_k v (k + 1)
    | HUn (op, inner) -> with_hexpr_desc h (HUn (op, go inner))
    | HArithBin (op, a, b) -> with_hexpr_desc h (HArithBin (op, go a, go b))
    | HBoolBin (op, a, b) -> with_hexpr_desc h (HBoolBin (op, go a, go b))
    | HCmp (op, a, b) -> with_hexpr_desc h (HCmp (op, go a, go b))
  in
  go h

let shift_hexpr_backward_all (h : hexpr) : hexpr =
  let rec go (h : hexpr) =
    match h.hexpr with
    | HLitInt _ | HLitBool _ -> h
    | HVar _ -> h
    | HPreK (v, k) -> if k <= 1 then mk_hvar v else mk_hpre_k v (k - 1)
    | HUn (op, inner) -> with_hexpr_desc h (HUn (op, go inner))
    | HArithBin (op, a, b) -> with_hexpr_desc h (HArithBin (op, go a, go b))
    | HBoolBin (op, a, b) -> with_hexpr_desc h (HBoolBin (op, go a, go b))
    | HCmp (op, a, b) -> with_hexpr_desc h (HCmp (op, go a, go b))
  in
  go h

let shift_fo_forward_all (f : fo_atom) : fo_atom =
  match f with
  | FRel (h1, r, h2) -> FRel (shift_hexpr_forward_all h1, r, shift_hexpr_forward_all h2)
  | FPred (id, hs) -> FPred (id, List.map shift_hexpr_forward_all hs)

let shift_fo_backward_all (f : fo_atom) : fo_atom =
  match f with
  | FRel (h1, r, h2) -> FRel (shift_hexpr_backward_all h1, r, shift_hexpr_backward_all h2)
  | FPred (id, hs) -> FPred (id, List.map shift_hexpr_backward_all hs)
