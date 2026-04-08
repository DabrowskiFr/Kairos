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

(** Core abstract syntax tree for Kairos programs, expressions, temporal
    formulas, and contract annotations. *)

(** {1 AST Overview}

   This module defines the source-level syntax tree shared by the frontend.

   Structural overview:
   {v
   program
     -> node
     -> transition
     -> stmt

   node
     -> semantics
     -> specification
   v}

   The sections below follow the language structure:
   {ul
   {- expressions;}
   {- temporal formulas;}
   {- statements;}
   {- invariants;}
   {- program structure.}} *)

(** {1 Core Types}

    Shared core syntax exported from {!module-Core_syntax}. *)

type ident = Core_syntax.ident [@@deriving yojson]

type ty = Core_syntax.ty =
  | TInt
  | TBool
  | TReal
  | TCustom of string
[@@deriving yojson]

type binop = Core_syntax.binop =
  | Add
  | Sub
  | Mul
  | Div
  | Eq
  | Neq
  | Lt
  | Le
  | Gt
  | Ge
  | And
  | Or
[@@deriving yojson]

type unop = Core_syntax.unop = Neg | Not [@@deriving yojson]

type loc = Core_syntax.loc = {
  line : int;
  col : int;
  line_end : int;
  col_end : int;
}
[@@deriving yojson]

type iexpr = Core_syntax.iexpr = {
  iexpr : iexpr_desc;
  loc : loc option;
}
[@@deriving yojson]

and iexpr_desc = Core_syntax.iexpr_desc =
  | ILitInt of int
  | ILitBool of bool
  | IVar of ident
  | IBin of binop * iexpr * iexpr
  | IUn of unop * iexpr
  | IPar of iexpr
[@@deriving yojson]

type hexpr = Core_syntax.hexpr = HNow of iexpr | HPreK of iexpr * int [@@deriving yojson]

type relop = Core_syntax.relop = REq | RNeq | RLt | RLe | RGt | RGe [@@deriving yojson]

type fo_atom = Core_syntax.fo_atom =
  | FRel of hexpr * relop * hexpr
  | FPred of ident * hexpr list
[@@deriving yojson]

type ltl = Core_syntax.ltl =
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

type ltl_o = Core_syntax.ltl_o = {
  value : ltl;
  oid : int;
  loc : loc option;
}
[@@deriving yojson]

type vdecl = Core_syntax.vdecl = {
  vname : ident;
  vty : ty;
}
[@@deriving yojson]

type invariant_user = Core_syntax.invariant_user = {
  inv_id : ident;
  inv_expr : hexpr;
}
[@@deriving show, yojson]

type invariant_state_rel = Core_syntax.invariant_state_rel = {
  state : ident;
  formula : ltl;
}
[@@deriving show, yojson]

(** {1 Statements & Invariants} *)

(** Executable statements. *)
type stmt = { stmt : stmt_desc; loc : loc option }
[@@deriving yojson]

and stmt_desc =
  | SAssign of ident * iexpr
  | SIf of iexpr * stmt list * stmt list
  | SMatch of iexpr * (ident * stmt list) list * stmt list
  | SSkip
  | SCall of ident * iexpr list * ident list
[@@deriving yojson]

(** {1 Per-pass Metadata}

    Per-pass metadata is documented in {!module-Stage_info} and kept separate
    from the AST. *)

(** {1 Program Structure} *)

(** Source transition. *)
type transition = {
  src : ident;
  dst : ident;
  guard : iexpr option;
  body : stmt list;
}

(** Program-facing part of a node: state machine and transition semantics. *)
type node_semantics = {
  sem_nname : ident;
  sem_inputs : vdecl list;
  sem_outputs : vdecl list;
  sem_instances : (ident * ident) list;
  sem_locals : vdecl list;
  sem_states : ident list;
  sem_init_state : ident;
  sem_trans : transition list;
}

(** Specification-facing part of a node.

    Formulas may refer to the current tick through [HNow] and to bounded
    history through [HPreK]. *)
type node_specification = {
  spec_assumes : ltl list;
  spec_guarantees : ltl list;
  spec_invariants_state_rel : invariant_state_rel list;
}

(** Source node. *)
type node = {
  semantics : node_semantics;
  specification : node_specification;
}

(** A program is a list of nodes. *)
type program = node list

(** {2 Utilities}

    Structural queries live in {!module-Ast_queries}. *)

val semantics_of_node : node -> node_semantics
val specification_of_node : node -> node_specification

(** Debug string representation of a program, mainly used for dumps. *)
val show_program : program -> string
