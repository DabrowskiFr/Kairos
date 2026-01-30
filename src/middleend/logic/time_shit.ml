(*---------------------------------------------------------------------------
 * Tempo - synchronous runtime for OCaml
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

open Ast

let shift_hexpr_forward ~init_for_var:(_init_for_var:ident -> iexpr)
  ~(is_input:ident -> bool) (h:hexpr) : hexpr =
  match h with
  | HNow (IVar v) when is_input v ->
      HPreK (IVar v, 1)
  | HNow _ -> h
  | HPreK (e, k) ->
      HPreK (e, k + 1)
  | HFold _ -> h

let rec shift_fo_forward_inputs ~init_for_var:(_init_for_var:ident -> iexpr)
  ~(is_input:ident -> bool) (f:fo) : fo =
  match f with
  | FTrue | FFalse -> f
  | FNot a -> FNot (shift_fo_forward_inputs ~init_for_var:_init_for_var ~is_input a)
  | FAnd (a, b) ->
      FAnd (shift_fo_forward_inputs ~init_for_var:_init_for_var ~is_input a,
            shift_fo_forward_inputs ~init_for_var:_init_for_var ~is_input b)
  | FOr (a, b) ->
      FOr (shift_fo_forward_inputs ~init_for_var:_init_for_var ~is_input a,
           shift_fo_forward_inputs ~init_for_var:_init_for_var ~is_input b)
  | FImp (a, b) ->
      FImp (shift_fo_forward_inputs ~init_for_var:_init_for_var ~is_input a,
            shift_fo_forward_inputs ~init_for_var:_init_for_var ~is_input b)
  | FRel (h1, r, h2) ->
      FRel (shift_hexpr_forward ~init_for_var:_init_for_var ~is_input h1, r,
            shift_hexpr_forward ~init_for_var:_init_for_var ~is_input h2)
  | FPred (id, hs) ->
      FPred (id, List.map (shift_hexpr_forward ~init_for_var:_init_for_var ~is_input) hs)

let shift_hexpr_backward ~(is_input:ident -> bool) (h:hexpr) : hexpr =
  match h with
  | HNow (IVar v) when is_input v -> HNow (IVar v)
  | HNow _ -> h
  | HPreK (IVar v, k) when is_input v ->
      if k <= 1 then HNow (IVar v) else HPreK (IVar v, k - 1)
  | HPreK _ -> h
  | HFold _ -> h

let rec shift_fo_backward_inputs ~(is_input:ident -> bool) (f:fo) : fo =
  match f with
  | FTrue | FFalse -> f
  | FNot a -> FNot (shift_fo_backward_inputs ~is_input a)
  | FAnd (a, b) ->
      FAnd (shift_fo_backward_inputs ~is_input a,
            shift_fo_backward_inputs ~is_input b)
  | FOr (a, b) ->
      FOr (shift_fo_backward_inputs ~is_input a,
           shift_fo_backward_inputs ~is_input b)
  | FImp (a, b) ->
      FImp (shift_fo_backward_inputs ~is_input a,
            shift_fo_backward_inputs ~is_input b)
  | FRel (h1, r, h2) ->
      FRel (shift_hexpr_backward ~is_input h1, r,
            shift_hexpr_backward ~is_input h2)
  | FPred (id, hs) ->
      FPred (id, List.map (shift_hexpr_backward ~is_input) hs)

let[@warning "-32"] rec shift_ltl_forward_inputs ~init_for_var:(_init_for_var:ident -> iexpr)
  ~(is_input:ident -> bool) (f:ltl) : ltl =
  match f with
  | LTrue | LFalse -> f
  | LNot a -> LNot (shift_ltl_forward_inputs ~init_for_var:_init_for_var ~is_input a)
  | LAnd (a, b) ->
      LAnd (shift_ltl_forward_inputs ~init_for_var:_init_for_var ~is_input a,
            shift_ltl_forward_inputs ~init_for_var:_init_for_var ~is_input b)
  | LOr (a, b) ->
      LOr (shift_ltl_forward_inputs ~init_for_var:_init_for_var ~is_input a,
           shift_ltl_forward_inputs ~init_for_var:_init_for_var ~is_input b)
  | LImp (a, b) ->
      LImp (shift_ltl_forward_inputs ~init_for_var:_init_for_var ~is_input a,
            shift_ltl_forward_inputs ~init_for_var:_init_for_var ~is_input b)
  | LX a -> LX (shift_ltl_forward_inputs ~init_for_var:_init_for_var ~is_input a)
  | LG a -> LG (shift_ltl_forward_inputs ~init_for_var:_init_for_var ~is_input a)
  | LAtom f -> LAtom (shift_fo_forward_inputs ~init_for_var:_init_for_var ~is_input f)
