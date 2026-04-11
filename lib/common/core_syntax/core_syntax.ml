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

(** {1 Core syntax}

    This module defines the shared syntax core used by the frontend,
    middle-end, and backends. It separates two expression layers:
    - [expr]: executable expressions.
    - [hexpr]: historical/logical expressions. *)

(** Identifiers (variables, states, symbols). *)
type ident = string 
  [@@deriving yojson]

(** Source types supported by the core. *)
type ty = TInt | TBool | TReal | TCustom of string 
  [@@deriving yojson]

(** Binary operators. *)
type binop = Add | Sub | Mul | Div | And | Or
  [@@deriving yojson]

(** Unary operators. *)
type unop = Neg | Not
  [@@deriving yojson]

(** Comparison operators. *)
type relop = REq | RNeq | RLt | RLe | RGt | RGe 
  [@@deriving yojson]

(** Imperative/executable expression.

    Used in transition guards and imperative statements. *)
type expr = { expr : expr_desc; loc : Loc.loc option }

and expr_desc =
  | ELitInt of int
  | ELitBool of bool
  | EVar of ident
  | EBin of binop * expr * expr
  | ECmp of relop * expr * expr
  | EUn of unop * expr
[@@deriving yojson]

(** Historical/logical expression.

    Used in first-order atoms. [HPreK (x, k)] denotes the value of [x]
    [k] steps in the past. *)
type hexpr = { hexpr : hexpr_desc; loc : Loc.loc option }

and hexpr_desc =
  | HLitInt of int
  | HLitBool of bool
  | HVar of ident
  | HPreK of ident * int
  | HPred of ident * hexpr list
  | HBin of binop * hexpr * hexpr
  | HCmp of relop * hexpr * hexpr
  | HUn of unop * hexpr
[@@deriving yojson]

(** First-order logic atom. *)
type fo_atom =
  | FRel of hexpr * relop * hexpr
  | FPred of ident * hexpr list
[@@deriving yojson]

(** LTL formulas (safety-oriented fragment used by the tool). *)
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

(** LTL formula tagged with a stable identifier and optional source location
    (diagnostic/render traceability). *)
type ltl_o = { value : ltl; oid : int; loc : Loc.loc option } [@@deriving yojson]

(** Typed variable declaration. *)
type vdecl = { vname : ident; vty : ty } [@@deriving yojson]
