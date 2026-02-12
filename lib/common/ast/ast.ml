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

type ident = string [@@deriving show]
type ty = TInt | TBool | TReal | TCustom of string [@@deriving show]
type binop = Add | Sub | Mul | Div | Eq | Neq | Lt | Le | Gt | Ge | And | Or [@@deriving show]
type unop = Neg | Not [@@deriving show]
(* fold removed: op type no longer used *)

type loc = { line : int; col : int; line_end : int; col_end : int } [@@deriving show]

type iexpr = { iexpr : iexpr_desc; loc : loc option }

and iexpr_desc =
  | ILitInt of int
  | ILitBool of bool
  | IVar of ident
  | IBin of binop * iexpr * iexpr
  | IUn of unop * iexpr
  | IPar of iexpr
[@@deriving show]

type hexpr = HNow of iexpr | HPreK of iexpr * int (* pre_k(e, k) *) [@@deriving show]
type relop = REq | RNeq | RLt | RLe | RGt | RGe [@@deriving show]

type fo =
  | FTrue
  | FFalse
  | FRel of hexpr * relop * hexpr
  | FPred of ident * hexpr list
  | FNot of fo
  | FAnd of fo * fo
  | FOr of fo * fo
  | FImp of fo * fo
[@@deriving show]

type 'a ltl =
  | LTrue
  | LFalse
  | LAtom of 'a
  | LNot of 'a ltl
  | LAnd of 'a ltl * 'a ltl
  | LOr of 'a ltl * 'a ltl
  | LImp of 'a ltl * 'a ltl
  | LX of 'a ltl (* Next *)
  | LG of 'a ltl (* Globally *)
[@@deriving show]

type fo_ltl = fo ltl [@@deriving show]
type atom_ltl = ident ltl [@@deriving show]
type origin =
  | UserContract
  | Monitor
  | Coherency
  | Compatibility
  | AssumeAutomaton
  | Internal
[@@deriving show]
type fo_o = { value : fo; origin : origin option; oid : int; loc : loc option } [@@deriving show]
type vdecl = { vname : ident; vty : ty } [@@deriving show]

type stmt = { stmt : stmt_desc; loc : loc option }

and stmt_desc =
  | SAssign of ident * iexpr
  | SIf of iexpr * stmt list * stmt list
  | SMatch of iexpr * (ident * stmt list) list * stmt list
  | SSkip
  | SCall of ident * iexpr list * ident list
[@@deriving show]

type invariant_user = { inv_id : ident; inv_expr : hexpr } [@@deriving show]
type invariant_state_rel = { is_eq : bool; state : ident; formula : fo } [@@deriving show]

type node_attrs = {
  uid : int option;
  invariants_user : invariant_user list;
  invariants_state_rel : invariant_state_rel list;
  coherency_goals : fo_o list;
}
[@@deriving show]

type transition_attrs = {
  uid : int option;
  ghost : stmt list;
  monitor : stmt list;
  warnings : string list;
}
[@@deriving show]

type transition = {
  src : ident;
  dst : ident;
  guard : iexpr option;
  requires : fo_o list;
  ensures : fo_o list;
  body : stmt list;
  attrs : transition_attrs;
}
[@@deriving show]

type node = {
  nname : ident;
  inputs : vdecl list;
  outputs : vdecl list;
  assumes : fo_ltl list;
  guarantees : fo_ltl list;
  instances : (ident * ident) list;
  locals : vdecl list;
  states : ident list;
  init_state : ident;
  trans : transition list;
  attrs : node_attrs;
}
[@@deriving show]

type program = node list [@@deriving show]
