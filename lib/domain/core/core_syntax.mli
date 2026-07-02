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

(** Core syntax shared by the frontend, reference verification passes and
    backends.

    The proof-relevant boundary starts after source syntactic sugar has been
    lowered into these definitions.  [expr] is executable syntax used by guards
    and statements; [hexpr] is the first-order historical assertion layer used
    by contracts, automata guards and proof obligations. *)

(** Identifiers for variables, states and symbols. *)
type ident = string [@@deriving yojson]

(** Source-level value types represented in the core. *)
type ty = TInt | TBool | TReal | TCustom of string [@@deriving yojson]

(** Finite algebraic type declaration. *)
type enum_decl = {
  enum_name : ident;
  enum_constructors : ident list;
}
[@@deriving yojson]

(** Binary operators shared by executable and assertion expressions. *)
type binop = Add | Sub | Mul | Div | And | Or [@@deriving yojson]

(** Unary operators shared by executable and assertion expressions. *)
type unop = Neg | Not [@@deriving yojson]

(** First-order comparison operators. *)
type relop = REq | RNeq | RLt | RLe | RGt | RGe [@@deriving yojson]

(** Imperative expression used in guards and statements. *)
type expr = { expr : expr_desc; loc : Loc.loc option }

and expr_desc =
  | ELitInt of int
  | ELitBool of bool
  | ELitEnum of ident
  | EVar of ident
  | EFunCall of ident * expr list
  | EBin of binop * expr * expr
  | ECmp of relop * expr * expr
  | EUn of unop * expr
[@@deriving yojson]

(** Historical/logical expression used in first-order atoms. *)
type hexpr = { hexpr : hexpr_desc; loc : Loc.loc option }

and hexpr_desc =
  | HLitInt of int
  | HLitBool of bool
  | HLitEnum of ident
  | HVar of ident
  | HPreK of ident * int
  | HPred of ident * hexpr list
  | HFunCall of ident * hexpr list
  | HBin of binop * hexpr * hexpr
  | HCmp of relop * hexpr * hexpr
  | HUn of unop * hexpr
[@@deriving yojson]

(** Atomic LTL predicate over historical expressions. *)
type ltl_atom = hexpr * relop * hexpr [@@deriving yojson]

(** Temporal contract formulas consumed by the automata/product pipeline. *)
type ltl =
  | LTrue
  | LFalse
  | LAtom of ltl_atom
  | LNot of ltl
  | LAnd of ltl * ltl
  | LOr of ltl * ltl
  | LImp of ltl * ltl
  | LX of ltl
  | LG of ltl
  | LW of ltl * ltl
[@@deriving yojson]

(** LTL formula tagged with a stable identifier and optional source location. *)
type ltl_o = { value : ltl; oid : int; loc : Loc.loc option }
[@@deriving yojson]

(** Typed variable declaration. *)
type vdecl = { vname : ident; vty : ty } [@@deriving yojson]

(** Pure first-order function declaration. *)
type pure_function_decl = {
  function_name : ident;
  function_params : vdecl list;
  function_return : ty;
  function_requires : hexpr list;
  function_ensures : hexpr list;
  function_body : expr;
}
[@@deriving yojson]

(** Internal imperative statement language used by the verification model and
    downstream execution/proof views. *)
type stmt = { stmt : stmt_desc; loc : Loc.loc option }

and stmt_desc =
  | SAssign of ident * expr
  | SAssert of hexpr
  | SIf of expr * stmt list * stmt list
  | SWhile of expr * hexpr list * expr option * stmt list
  | SMatch of expr * (ident * stmt list) list * stmt list
  | SSkip
  | SCall of ident * expr list * ident list
[@@deriving yojson]
