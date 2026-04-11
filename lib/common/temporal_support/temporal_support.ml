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
open Core_syntax_builders

type pre_k_info = { var_name : ident; names : string list; vty : ty } [@@deriving yojson]

type ltl_norm = { ltl : ltl; k_guard : int option }

let rec max_x_depth (f : ltl) : int =
  match f with
  | LX a -> 1 + max_x_depth a
  | LTrue | LFalse | LAtom _ -> 0
  | LNot a | LG a -> max_x_depth a
  | LAnd (a, b) | LOr (a, b) | LImp (a, b) | LW (a, b) -> max (max_x_depth a) (max_x_depth b)

let is_const_expr (e : expr) : bool =
  match e.expr with
  | ELitInt _ | ELitBool _ -> true
  | EVar name ->
      let len = String.length name in
      len >= 4
      && String.sub name 0 3 = "Aut"
      && String.for_all (function '0' .. '9' -> true | _ -> false) (String.sub name 3 (len - 3))
  | _ -> false

let rec shift_hexpr_by ~(init_for_var : ident -> expr) (shift : int) (h : hexpr) : hexpr option =
  let _ = init_for_var in
  if shift <= 0 then Some h
  else
    match h.hexpr with
    | HLitInt _ | HLitBool _ -> Some h
    | HVar v -> Some (mk_hpre_k v shift)
    | HPreK (v, k) -> Some (mk_hpre_k v (k + shift))
    | HPred (id, hs) ->
        let rec map acc = function
          | [] -> Some (List.rev acc)
          | x :: xs -> (
              match shift_hexpr_by ~init_for_var shift x with
              | Some x' -> map (x' :: acc) xs
              | None -> None)
        in
        Option.map (fun hs' -> with_hexpr_desc h (HPred (id, hs'))) (map [] hs)
    | HUn (op, inner) ->
        Option.map
          (fun inner' -> with_hexpr_desc h (HUn (op, inner')))
          (shift_hexpr_by ~init_for_var shift inner)
    | HBin (op, a, b) -> (
        match (shift_hexpr_by ~init_for_var shift a, shift_hexpr_by ~init_for_var shift b) with
        | Some a', Some b' -> Some (with_hexpr_desc h (HBin (op, a', b')))
        | _ -> None)
    | HCmp (op, a, b) -> (
        match (shift_hexpr_by ~init_for_var shift a, shift_hexpr_by ~init_for_var shift b) with
        | Some a', Some b' -> Some (with_hexpr_desc h (HCmp (op, a', b')))
        | _ -> None)

let normalize_ltl_for_k ~(init_for_var : ident -> expr) (f : ltl) : ltl_norm =
  let rec shift_ltl_with_depth k depth f =
    match f with
    | LX a -> shift_ltl_with_depth k (depth + 1) a
    | LTrue | LFalse -> Some f
    | LNot a -> Option.map (fun a' -> LNot a') (shift_ltl_with_depth k depth a)
    | LAnd (a, b) -> begin
        match (shift_ltl_with_depth k depth a, shift_ltl_with_depth k depth b) with
        | Some a', Some b' -> Some (LAnd (a', b'))
        | _ -> None
      end
    | LOr (a, b) -> begin
        match (shift_ltl_with_depth k depth a, shift_ltl_with_depth k depth b) with
        | Some a', Some b' -> Some (LOr (a', b'))
        | _ -> None
      end
    | LImp (a, b) -> begin
        match (shift_ltl_with_depth k depth a, shift_ltl_with_depth k depth b) with
        | Some a', Some b' -> Some (LImp (a', b'))
        | _ -> None
      end
    | LW (a, b) -> begin
        match (shift_ltl_with_depth k depth a, shift_ltl_with_depth k depth b) with
        | Some a', Some b' -> Some (LW (a', b'))
        | _ -> None
      end
    | LG a -> Option.map (fun a' -> LG a') (shift_ltl_with_depth k depth a)
    | LAtom (h1, r, h2) ->
        let shift = k - depth in
        begin match (shift_hexpr_by ~init_for_var shift h1, shift_hexpr_by ~init_for_var shift h2) with
        | Some h1', Some h2' -> Some (LAtom (h1', r, h2'))
        | _ -> None
        end
  in
  let k = max_x_depth f in
  if k = 0 then { ltl = f; k_guard = None }
  else
    match shift_ltl_with_depth k 0 f with
    | Some ltl -> { ltl; k_guard = Some k }
    | None -> { ltl = f; k_guard = Some k }

let rec shift_ltl_by ~(init_for_var : ident -> expr) (shift : int) (f : ltl) : ltl option =
  if shift <= 0 then Some f
  else
    match f with
    | LX a -> shift_ltl_by ~init_for_var (shift + 1) a
    | LTrue | LFalse -> Some f
    | LNot a -> Option.map (fun a' -> LNot a') (shift_ltl_by ~init_for_var shift a)
    | LAnd (a, b) -> begin
        match (shift_ltl_by ~init_for_var shift a, shift_ltl_by ~init_for_var shift b) with
        | Some a', Some b' -> Some (LAnd (a', b'))
        | _ -> None
      end
    | LOr (a, b) -> begin
        match (shift_ltl_by ~init_for_var shift a, shift_ltl_by ~init_for_var shift b) with
        | Some a', Some b' -> Some (LOr (a', b'))
        | _ -> None
      end
    | LImp (a, b) -> begin
        match (shift_ltl_by ~init_for_var shift a, shift_ltl_by ~init_for_var shift b) with
        | Some a', Some b' -> Some (LImp (a', b'))
        | _ -> None
      end
    | LW (a, b) -> begin
        match (shift_ltl_by ~init_for_var shift a, shift_ltl_by ~init_for_var shift b) with
        | Some a', Some b' -> Some (LW (a', b'))
        | _ -> None
      end
    | LG a -> Option.map (fun a' -> LG a') (shift_ltl_by ~init_for_var shift a)
    | LAtom (h1, r, h2) -> begin
        match (shift_hexpr_by ~init_for_var shift h1, shift_hexpr_by ~init_for_var shift h2) with
        | Some h1', Some h2' -> Some (LAtom (h1', r, h2'))
        | _ -> None
      end
