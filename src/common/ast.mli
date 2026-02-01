(*---------------------------------------------------------------------------
 * Tempo - synchronous runtime for OCaml
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

(** {1 Core Types} *)

type ident = string
type ty = TInt | TBool | TReal | TCustom of string
type binop = Add | Sub | Mul | Div | Eq | Neq | Lt | Le | Gt | Ge | And | Or
type unop = Neg | Not
type op = OMin | OMax | OAdd | OMul | OAnd | OOr | OFirst
type iexpr =
    ILitInt of int
  | ILitBool of bool
  | IVar of ident
  | IBin of binop * iexpr * iexpr
  | IUn of unop * iexpr
  | IPar of iexpr
type hexpr =
    HNow of iexpr
  | HPreK of iexpr * int
  | HFold of op * iexpr * iexpr
type relop = REq | RNeq | RLt | RLe | RGt | RGe

(** {1 Logical Formulas} *)
type fo =
    FTrue
  | FFalse
  | FRel of hexpr * relop * hexpr
  | FPred of ident * hexpr list
  | FNot of fo
  | FAnd of fo * fo
  | FOr of fo * fo
  | FImp of fo * fo
type 'a ltl =
    LTrue
  | LFalse
  | LAtom of 'a
  | LNot of 'a ltl
  | LAnd of 'a ltl * 'a ltl
  | LOr of 'a ltl * 'a ltl
  | LImp of 'a ltl * 'a ltl
  | LX of 'a ltl
  | LG of 'a ltl
type fo_ltl = fo ltl
type atom_ltl = ident ltl
type vdecl = { vname : ident; vty : ty; }

(** {1 Statements And Contracts} *)
type stmt =
    SAssign of ident * iexpr
  | SIf of iexpr * stmt list * stmt list
  | SMatch of iexpr * (ident * stmt list) list * stmt list
  | SSkip
  | SCall of ident * iexpr list * ident list
type invariant_mon =
    Invariant of ident * hexpr
  | InvariantStateRel of bool * ident * fo
type transition = {
  src : ident;
  dst : ident;
  guard : iexpr option;
  requires : fo list;
  ensures : fo list;
  lemmas : fo list;
  body : stmt list;
}
type node = {
  nname : ident;
  inputs : vdecl list;
  outputs : vdecl list;
  assumes : fo_ltl list;
  guarantees : fo_ltl list;
  invariants_mon : invariant_mon list;
  instances : (ident * ident) list;
  locals : vdecl list;
  states : ident list;
  init_state : ident;
  trans : transition list;
}
type program = node list

(** {1 Phase Markers} *)

type user_node = node
type internal_node = node
type user_program = program
type internal_program = program

(** {1 Debug Output} *)

(** Render a program using the derived [show] printer. *)
val show_program : program -> string
