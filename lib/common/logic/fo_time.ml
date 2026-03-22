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

open Ast
open Ast_builders

let shift_hexpr_forward ~(is_input : ident -> bool) (h : hexpr) : hexpr =
  match h with
  | HNow e -> begin match as_var e with Some v when is_input v -> HPreK (e, 1) | _ -> h end
  | HPreK (e, k) -> HPreK (e, k + 1)

let shift_hexpr_backward ~(is_input : ident -> bool) (h : hexpr) : hexpr =
  match h with
  | HNow e -> begin match as_var e with Some v when is_input v -> HNow e | _ -> h end
  | HPreK (e, k) -> begin
      match as_var e with
      | Some v when is_input v -> if k <= 1 then HNow e else HPreK (e, k - 1)
      | _ -> h
    end

let shift_fo_forward_inputs ~(is_input : ident -> bool) (f : fo) : fo =
  match f with
  | FRel (h1, r, h2) -> FRel (shift_hexpr_forward ~is_input h1, r, shift_hexpr_forward ~is_input h2)
  | FPred (id, hs) -> FPred (id, List.map (shift_hexpr_forward ~is_input) hs)

let shift_fo_backward_inputs ~(is_input : ident -> bool) (f : fo) : fo =
  match f with
  | FRel (h1, r, h2) ->
      FRel (shift_hexpr_backward ~is_input h1, r, shift_hexpr_backward ~is_input h2)
  | FPred (id, hs) -> FPred (id, List.map (shift_hexpr_backward ~is_input) hs)

let shift_hexpr_forward_all (h : hexpr) : hexpr =
  match h with
  | HNow e -> begin match as_var e with Some _ -> HPreK (e, 1) | None -> h end
  | HPreK (e, k) -> HPreK (e, k + 1)

let shift_hexpr_backward_all (h : hexpr) : hexpr =
  match h with HNow e -> HNow e | HPreK (e, k) -> if k <= 1 then HNow e else HPreK (e, k - 1)

let shift_fo_forward_all (f : fo) : fo =
  match f with
  | FRel (h1, r, h2) -> FRel (shift_hexpr_forward_all h1, r, shift_hexpr_forward_all h2)
  | FPred (id, hs) -> FPred (id, List.map shift_hexpr_forward_all hs)

let shift_fo_backward_all (f : fo) : fo =
  match f with
  | FRel (h1, r, h2) -> FRel (shift_hexpr_backward_all h1, r, shift_hexpr_backward_all h2)
  | FPred (id, hs) -> FPred (id, List.map shift_hexpr_backward_all hs)

let rec shift_ltl_forward_inputs ~(is_input : ident -> bool) (f : ltl) : ltl =
  let go = shift_ltl_forward_inputs ~is_input in
  match f with
  | LTrue | LFalse -> f
  | LAtom a -> LAtom (shift_fo_forward_inputs ~is_input a)
  | LNot a -> LNot (go a)
  | LAnd (a, b) -> LAnd (go a, go b)
  | LOr (a, b) -> LOr (go a, go b)
  | LImp (a, b) -> LImp (go a, go b)
  | LX a -> LX (go a)
  | LG a -> LG (go a)
  | LW (a, b) -> LW (go a, go b)
