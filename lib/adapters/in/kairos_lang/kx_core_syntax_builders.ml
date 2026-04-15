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

open Kx_core_syntax

let mk_expr ?loc expr = { expr; loc }
let with_expr_desc e expr = { e with expr }
let mk_var v = mk_expr (EVar v)
let mk_int n = mk_expr (ELitInt n)
let mk_bool b = mk_expr (ELitBool b)

let mk_hexpr ?loc hexpr = { hexpr; loc }
let with_hexpr_desc h hexpr = { h with hexpr }
let mk_hvar v = mk_hexpr (HVar v)
let mk_hint n = mk_hexpr (HLitInt n)
let mk_hbool b = mk_hexpr (HLitBool b)
let mk_hpre_k v k = mk_hexpr (HPreK (v, k))
let mk_hpred id args = mk_hexpr (HPred (id, args))
let mk_hnot h = mk_hexpr (HUn (Not, h))
let mk_hand a b = mk_hexpr (HBin (And, a, b))
let mk_hor a b = mk_hexpr (HBin (Or, a, b))
let mk_himp a b = mk_hor (mk_hnot a) b

let rec hexpr_of_expr (e : expr) : hexpr =
  let hexpr =
    match e.expr with
    | ELitInt n -> HLitInt n
    | ELitBool b -> HLitBool b
    | EVar v -> HVar v
    | EBin (op, a, b) -> HBin (op, hexpr_of_expr a, hexpr_of_expr b)
    | ECmp (op, a, b) -> HCmp (op, hexpr_of_expr a, hexpr_of_expr b)
    | EUn (op, inner) -> HUn (op, hexpr_of_expr inner)
  in
  { hexpr; loc = e.loc }
