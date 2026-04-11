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

type ident = string [@@deriving yojson]

type ty = TInt | TBool | TReal | TCustom of string [@@deriving yojson]

(* type binop = Add | Sub | Mul | Div | Eq | Neq | Lt | Le | Gt | Ge | And | Or [@@deriving yojson] *)

(* type unop = Neg | Not [@@deriving yojson] *)

type loc = { line : int; col : int; line_end : int; col_end : int } [@@deriving yojson]

type binop =
  | Add
  | Sub
  | Mul
  | Div
[@@deriving yojson]

type bool_binop =
  | And
  | Or
[@@deriving yojson]

type unop =
  | Neg
  | Not
[@@deriving yojson]

type relop = REq | RNeq | RLt | RLe | RGt | RGe [@@deriving yojson]


type iexpr = { iexpr : iexpr_desc; loc : loc option }

and iexpr_desc =
  | ILitInt of int
  | ILitBool of bool
  | IVar of ident
  | IArithBin of binop * iexpr * iexpr
  | IBoolBin of bool_binop * iexpr * iexpr
  | ICmp of relop * iexpr * iexpr
  | IUn of unop * iexpr
[@@deriving yojson]

(* type hbinop =
  | HAdd
  | HSub
  | HMul
  | HDiv
[@@deriving yojson]

type hbool_binop =
  | HAnd
  | HOr
[@@deriving yojson]

type hunop =
  | HNeg
  | HNot
[@@deriving yojson] *)

type hexpr = { hexpr : hexpr_desc; loc : loc option }

and hexpr_desc =
  | HLitInt of int
  | HLitBool of bool
  | HVar of ident
  | HPreK of ident * int
  | HArithBin of binop * hexpr * hexpr
  | HBoolBin of bool_binop * hexpr * hexpr
  | HCmp of relop * hexpr * hexpr
  | HUn of unop * hexpr
[@@deriving yojson]

type fo_atom =
  | FRel of hexpr * relop * hexpr
  | FPred of ident * hexpr list
[@@deriving yojson]

type ltl =
  | LTrue
  | LFalse
  | LAtom of fo_atom
  | LNot of ltl
  | LAnd of ltl * ltl
  | LOr of ltl * ltl
  | LImp of ltl * ltl
  | LX of ltl
  | LG of ltl
  | LW of ltl * ltl
[@@deriving yojson]

type ltl_o = { value : ltl; oid : int; loc : loc option } [@@deriving yojson]
type vdecl = { vname : ident; vty : ty } [@@deriving yojson]
