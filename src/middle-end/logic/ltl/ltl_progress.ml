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

let eval_atom (_atom_map:(fo * ident) list) (vals:(string * bool) list) (f:fo)
  : bool =
  match f with
  | FRel (HNow a, REq, HNow b) ->
      begin match as_var a, b.iexpr with
      | Some name, ILitBool true -> Ltl_valuation.lookup_val vals name
      | _ -> false
      end
  | _ -> false

let rec progress_ltl (atom_map:(fo * ident) list) (vals:(string * bool) list) (f:fo_ltl)
  : fo_ltl =
  let f =
    match f with
    | LTrue | LFalse -> f
    | LAtom a -> if eval_atom atom_map vals a then LTrue else LFalse
    | LNot a -> LNot (progress_ltl atom_map vals a)
    | LAnd (a,b) -> LAnd (progress_ltl atom_map vals a, progress_ltl atom_map vals b)
    | LOr (a,b) -> LOr (progress_ltl atom_map vals a, progress_ltl atom_map vals b)
    | LImp (a,b) -> LImp (progress_ltl atom_map vals a, progress_ltl atom_map vals b)
    | LX a -> a
    | LG a ->
        let a_now = progress_ltl atom_map vals a in
        LAnd (a_now, LG a)
  in
  Ltl_norm.simplify_ltl f
