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

module C = Core_syntax

let rec split_top_level_or (f : C.hexpr) : C.hexpr list =
  match f.hexpr with
  | C.HBin (C.Or, a, b) -> split_top_level_or a @ split_top_level_or b
  | _ -> [ f ]

let rec normalize_phase_summary (f : C.hexpr) : C.hexpr =
  match f.hexpr with
  | C.HLitInt _ | C.HLitBool _ | C.HLitEnum _ | C.HVar _ | C.HPreK _ | C.HPred _ -> f
  | C.HFunCall (fn, hs) ->
      Core_syntax_builders.with_hexpr_desc f (C.HFunCall (fn, List.map normalize_phase_summary hs))
  | C.HUn (op, inner) ->
      Core_syntax_builders.with_hexpr_desc f (C.HUn (op, normalize_phase_summary inner))
  | C.HBin (op, a, b) ->
      Core_syntax_builders.with_hexpr_desc f
        (C.HBin (op, normalize_phase_summary a, normalize_phase_summary b))
  | C.HCmp (r, a, b) ->
      Core_syntax_builders.with_hexpr_desc f
        (C.HCmp (r, normalize_phase_summary a, normalize_phase_summary b))

let rec normalize_source_summary (f : C.hexpr) : C.hexpr =
  match f.hexpr with
  | C.HLitInt _ | C.HLitBool _ | C.HLitEnum _ | C.HVar _ | C.HPreK _ | C.HPred _ -> f
  | C.HFunCall (fn, hs) ->
      Core_syntax_builders.with_hexpr_desc f (C.HFunCall (fn, List.map normalize_source_summary hs))
  | C.HUn (C.Neg, inner) ->
      Core_syntax_builders.with_hexpr_desc f (C.HUn (C.Neg, normalize_source_summary inner))
  | C.HUn (C.Not, inner) -> (
      match normalize_source_summary inner with
      | { C.hexpr = C.HLitBool true; _ } -> Core_syntax_builders.mk_hbool false
      | { C.hexpr = C.HLitBool false; _ } -> Core_syntax_builders.mk_hbool true
      | inner' -> Core_syntax_builders.mk_hnot inner')
  | C.HBin (C.And, a, b) ->
      begin match (normalize_source_summary a, normalize_source_summary b) with
      | ({ C.hexpr = C.HLitBool false; _ } as x), _ -> x
      | _, ({ C.hexpr = C.HLitBool false; _ } as x) -> x
      | { C.hexpr = C.HLitBool true; _ }, rhs -> rhs
      | lhs, { C.hexpr = C.HLitBool true; _ } -> lhs
      | lhs, rhs -> Core_syntax_builders.mk_hand lhs rhs
      end
  | C.HBin (C.Or, a, b) ->
      begin match (normalize_source_summary a, normalize_source_summary b) with
      | ({ C.hexpr = C.HLitBool true; _ } as x), _ -> x
      | _, ({ C.hexpr = C.HLitBool true; _ } as x) -> x
      | { C.hexpr = C.HLitBool false; _ }, rhs -> rhs
      | lhs, { C.hexpr = C.HLitBool false; _ } -> lhs
      | lhs, rhs -> Core_syntax_builders.mk_hor lhs rhs
      end
  | C.HBin (op, a, b) ->
      Core_syntax_builders.with_hexpr_desc f
        (C.HBin (op, normalize_source_summary a, normalize_source_summary b))
  | C.HCmp (r, a, b) ->
      Core_syntax_builders.with_hexpr_desc f
        (C.HCmp (r, normalize_source_summary a, normalize_source_summary b))

let term_or a b = normalize_source_summary (Core_syntax_builders.mk_hor a b)
let term_and a b = normalize_source_summary (Core_syntax_builders.mk_hand a b)
let term_not a = normalize_source_summary (Core_syntax_builders.mk_hnot a)

let rec phase_summary_obviously_inconsistent (f : C.hexpr) : bool =
  match normalize_source_summary f with
  | { C.hexpr = C.HLitBool false; _ } -> true
  | { C.hexpr = C.HCmp (C.RNeq, { C.hexpr = C.HVar x; _ }, { C.hexpr = C.HVar y; _ }); _ }
    when String.equal x y ->
      true
  | {
   C.hexpr =
     C.HUn
       (C.Not, { C.hexpr = C.HCmp (C.REq, { C.hexpr = C.HVar x; _ }, { C.hexpr = C.HVar y; _ }); _ });
   _;
  }
    when String.equal x y ->
      true
  | { C.hexpr = C.HUn (C.Not, { C.hexpr = C.HLitBool true; _ }); _ } -> true
  | { C.hexpr = C.HBin (C.And, a, b); _ } ->
      phase_summary_obviously_inconsistent a || phase_summary_obviously_inconsistent b
  | _ -> false
