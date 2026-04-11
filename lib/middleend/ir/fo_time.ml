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
open Core_syntax_builders

let shift_hexpr_forward ~(is_input : ident -> bool) (h : hexpr) : hexpr =
  let rec go (h : hexpr) =
    match h.hexpr with
    | HLitInt _ | HLitBool _ -> h
    | HVar v -> if is_input v then mk_hpre_k v 1 else h
    | HPreK (v, k) -> mk_hpre_k v (k + 1)
    | HPred (id, hs) -> with_hexpr_desc h (HPred (id, List.map go hs))
    | HUn (op, inner) -> with_hexpr_desc h (HUn (op, go inner))
    | HBin (op, a, b) -> with_hexpr_desc h (HBin (op, go a, go b))
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
    | HPred (id, hs) -> with_hexpr_desc h (HPred (id, List.map go hs))
    | HUn (op, inner) -> with_hexpr_desc h (HUn (op, go inner))
    | HBin (op, a, b) -> with_hexpr_desc h (HBin (op, go a, go b))
    | HCmp (op, a, b) -> with_hexpr_desc h (HCmp (op, go a, go b))
  in
  go h

let rec shift_formula_forward_inputs ~(is_input : ident -> bool) (f : Core_syntax.hexpr) :
    Core_syntax.hexpr =
  shift_hexpr_forward ~is_input f

let rec shift_formula_backward_inputs ~(is_input : ident -> bool) (f : Core_syntax.hexpr) :
    Core_syntax.hexpr =
  shift_hexpr_backward ~is_input f

let shift_hexpr_forward_all (h : hexpr) : hexpr =
  let rec go (h : hexpr) =
    match h.hexpr with
    | HLitInt _ | HLitBool _ -> h
    | HVar v -> mk_hpre_k v 1
    | HPreK (v, k) -> mk_hpre_k v (k + 1)
    | HPred (id, hs) -> with_hexpr_desc h (HPred (id, List.map go hs))
    | HUn (op, inner) -> with_hexpr_desc h (HUn (op, go inner))
    | HBin (op, a, b) -> with_hexpr_desc h (HBin (op, go a, go b))
    | HCmp (op, a, b) -> with_hexpr_desc h (HCmp (op, go a, go b))
  in
  go h

let shift_hexpr_backward_all (h : hexpr) : hexpr =
  let rec go (h : hexpr) =
    match h.hexpr with
    | HLitInt _ | HLitBool _ -> h
    | HVar _ -> h
    | HPreK (v, k) -> if k <= 1 then mk_hvar v else mk_hpre_k v (k - 1)
    | HPred (id, hs) -> with_hexpr_desc h (HPred (id, List.map go hs))
    | HUn (op, inner) -> with_hexpr_desc h (HUn (op, go inner))
    | HBin (op, a, b) -> with_hexpr_desc h (HBin (op, go a, go b))
    | HCmp (op, a, b) -> with_hexpr_desc h (HCmp (op, go a, go b))
  in
  go h
