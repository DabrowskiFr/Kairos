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

(** Core syntax shared by AST, IR, middle-end and backends. *)

type ident = string [@@deriving show, yojson]

type ty = TInt | TBool | TReal | TCustom of string [@@deriving show, yojson]

type binop = Add | Sub | Mul | Div | Eq | Neq | Lt | Le | Gt | Ge | And | Or [@@deriving show, yojson]

type unop = Neg | Not [@@deriving show, yojson]

type loc = { line : int; col : int; line_end : int; col_end : int } [@@deriving show, yojson]

type iexpr = { iexpr : iexpr_desc; loc : loc option }
[@@deriving show, yojson]

and iexpr_desc =
  | ILitInt of int
  | ILitBool of bool
  | IVar of ident
  | IBin of binop * iexpr * iexpr
  | IUn of unop * iexpr
  | IPar of iexpr
[@@deriving show, yojson]

type hexpr = HNow of iexpr | HPreK of iexpr * int [@@deriving show, yojson]

type relop = REq | RNeq | RLt | RLe | RGt | RGe [@@deriving show, yojson]

type fo_atom =
  | FRel of hexpr * relop * hexpr
  | FPred of ident * hexpr list
[@@deriving show, yojson]

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
[@@deriving show, yojson]

type ltl_o = { value : ltl; oid : int; loc : loc option } [@@deriving show, yojson]

type vdecl = { vname : ident; vty : ty } [@@deriving show, yojson]

type invariant_user = { inv_id : ident; inv_expr : hexpr } [@@deriving show, yojson]

type invariant_state_rel = { state : ident; formula : ltl } [@@deriving show, yojson]
