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
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *---------------------------------------------------------------------------*)

open Core_syntax
module Boolean = Core_fo_simplifier_bool
module Keys = Core_fo_simplifier_keys

let simplify_cache_limit = 20000

let simplify_cache : (string, Core_syntax.historical Core_syntax.hexpr) Hashtbl.t =
  Hashtbl.create 4096

let key_of_hexpr = Keys.key_of_hexpr

let rec simplify_uncached (f : Core_syntax.historical Core_syntax.hexpr) :
    Core_syntax.historical Core_syntax.hexpr =
  match f.hexpr with
  | HLitInt _ | HLitBool _ | HLitEnum _ | HVar _ | HPreK _ | HPred _ | HFunCall _ -> f
  | HUn (Neg, inner) -> Keys.mk_h (HUn (Neg, simplify inner))
  | HUn (Not, inner) ->
      begin match (simplify inner).hexpr with
      | HLitBool b -> Core_syntax_builders.mk_hbool (not b)
      | HUn (Not, nested) -> nested
      | HCmp (op, a, b) -> simplify (Keys.mk_h (HCmp (Keys.negate_relop op, a, b)))
      | HBin (And, a, b) ->
          Boolean.rebuild_or_syntax
            [ simplify (Core_syntax_builders.mk_hnot a); simplify (Core_syntax_builders.mk_hnot b) ]
      | HBin (Or, a, b) ->
          Boolean.rebuild_and_syntax
            [ simplify (Core_syntax_builders.mk_hnot a); simplify (Core_syntax_builders.mk_hnot b) ]
      | simplified -> Keys.mk_h (HUn (Not, { f with hexpr = simplified }))
      end
  | HBin (And, a, b) -> Boolean.rebuild_and_syntax [ simplify a; simplify b ]
  | HBin (Or, a, b) -> Boolean.rebuild_or_syntax [ simplify a; simplify b ]
  | HBin (op, a, b) -> Keys.mk_h (HBin (op, simplify a, simplify b))
  | HCmp (op, a, b) ->
      let a = simplify a in
      let b = simplify b in
      begin match Keys.eval_const_rel op a b with
      | Some value -> Core_syntax_builders.mk_hbool value
      | None when a = b ->
          Core_syntax_builders.mk_hbool
            (match op with REq | RLe | RGe -> true | RNeq | RLt | RGt -> false)
      | None ->
          begin match (op, a.hexpr, b.hexpr) with
          | REq, _, HLitBool true -> a
          | REq, HLitBool true, _ -> b
          | RNeq, _, HLitBool true -> simplify (Core_syntax_builders.mk_hnot a)
          | RNeq, HLitBool true, _ -> simplify (Core_syntax_builders.mk_hnot b)
          | REq, _, HLitBool false -> simplify (Core_syntax_builders.mk_hnot a)
          | REq, HLitBool false, _ -> simplify (Core_syntax_builders.mk_hnot b)
          | RNeq, _, HLitBool false -> a
          | RNeq, HLitBool false, _ -> b
          | _ -> Keys.mk_h (HCmp (op, a, b))
          end
      end

and simplify (f : Core_syntax.historical Core_syntax.hexpr) :
    Core_syntax.historical Core_syntax.hexpr =
  match f.hexpr with
  | HLitInt _ | HLitBool _ | HLitEnum _ | HVar _ | HPreK _ | HPred _ | HFunCall _ -> f
  | _ -> (
      let key = key_of_hexpr f in
      match Hashtbl.find_opt simplify_cache key with
      | Some cached -> cached
      | None ->
          let simplified = simplify_uncached f in
          if Hashtbl.length simplify_cache >= simplify_cache_limit then Hashtbl.clear simplify_cache;
          Hashtbl.replace simplify_cache key simplified;
          simplified)
