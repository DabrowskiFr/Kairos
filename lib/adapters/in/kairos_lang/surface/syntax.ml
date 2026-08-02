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

(** Expression and declaration fragments used by the surface AST.

    These types preserve indexed references, finite quantifiers and historical
    conveniences written by the user. [Ast] assembles them into the
    complete program produced by the parser. *)

include Shared.Syntax

type indexed_ref = {
  ref_base : ident;
  ref_indices : ident list;
}
[@@deriving yojson]

type raw_vdecl = {
  raw_vname : ident;
  raw_indices : ident list list option;
  raw_vty : ty;
}
[@@deriving yojson]

type typed_param = {
  param_name : ident;
  param_ty : ty;
}
[@@deriving yojson]

type method_param_mode = MPIn | MPInOut [@@deriving yojson]

type method_param = {
  method_param_name : ident;
  method_param_ty : ty;
  method_param_mode : method_param_mode;
}
[@@deriving yojson]

type spec_param_kind = SPFormula | SPHExpr | SPNat [@@deriving yojson]

type nat_expr =
  | SNNat of int
  | SNVar of ident
[@@deriving yojson]

type spec_param = {
  spec_param_name : ident;
  spec_param_kind : spec_param_kind;
}
[@@deriving yojson]

type expr = { sexpr : expr_desc; loc : Shared.Syntax.loc option }

and expr_desc =
  | SELitInt of int
  | SELitBool of bool
  | SEVar of indexed_ref
  | SEPre of indexed_ref
  | SECall of ident * expr list
  | SEBin of binop * expr * expr
  | SECmp of relop * expr * expr
  | SEUn of unop * expr
[@@deriving yojson]

type hexpr = { shexpr : hexpr_desc; hloc : Shared.Syntax.loc option }

and hexpr_desc =
  | SHLitInt of int
  | SHLitBool of bool
  | SHVar of indexed_ref
  | SHOld of hexpr
  | SHPreK of indexed_ref * nat_expr
  | SHPast of hexpr * nat_expr
  | SHHistoryAlias of ident * indexed_ref
  | SHCall of ident * hexpr list
  | SHExpr of expr
  | SHBin of binop * hexpr * hexpr
  | SHCmp of relop * hexpr * hexpr
  | SHUn of unop * hexpr
  | SHForall of ident * ident * hexpr
  | SHExists of ident * ident * hexpr
  | SHRangeForall of ident * nat_expr * nat_expr * hexpr
  | SHRangeExists of ident * nat_expr * nat_expr * hexpr
[@@deriving yojson]

type ltl =
  | SLTrue
  | SLFalse
  | SLAtom of hexpr * relop * hexpr
  | SLFo of hexpr
  | SLFormulaParam of ident
  | SLCall of ident * spec_arg list
  | SLNot of ltl
  | SLAnd of ltl * ltl
  | SLOr of ltl * ltl
  | SLImp of ltl * ltl
  | SLX of ltl
  | SLG of ltl
  | SLW of ltl * ltl
  | SLForall of ident * ident * ltl
  | SLExists of ident * ident * ltl
  | SLRangeForall of ident * nat_expr * nat_expr * ltl
  | SLRangeExists of ident * nat_expr * nat_expr * ltl
and spec_arg =
  | SAFormula of ltl
  | SAHExpr of hexpr
[@@deriving yojson]

type history_expr = { shistory_expr : history_expr_desc; hvloc : loc option }

and history_expr_desc =
  | SHValue of hexpr
  | SHIf of hexpr * history_expr * history_expr
[@@deriving yojson]

let mk_indexed_ref ref_base ref_indices = { ref_base; ref_indices }
let mk_scalar_ref ref_base = mk_indexed_ref ref_base []
let mk_history_expr ?loc shistory_expr = { shistory_expr; hvloc = loc }

let mk_expr ?loc sexpr = { sexpr; loc }
let mk_hexpr ?loc shexpr = { shexpr; hloc = loc }
