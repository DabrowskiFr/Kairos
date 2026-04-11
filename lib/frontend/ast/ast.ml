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

type relop = Core_syntax.relop = REq | RNeq | RLt | RLe | RGt | RGe [@@deriving yojson]

type ibinop = Core_syntax.ibinop =
  | IAdd
  | ISub
  | IMul
  | IDiv
[@@deriving yojson]

type ibool_binop = Core_syntax.ibool_binop =
  | IAnd
  | IOr
[@@deriving yojson]

type iunop = Core_syntax.iunop =
  | INeg
  | INot
[@@deriving yojson]

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

and iexpr_desc = Core_syntax.iexpr_desc =
  | ILitInt of int
  | ILitBool of bool
  | IVar of ident
  | IArithBin of ibinop * iexpr * iexpr
  | IBoolBin of ibool_binop * iexpr * iexpr
  | ICmp of relop * iexpr * iexpr
  | IUn of iunop * iexpr
[@@deriving yojson]

type hbinop = Core_syntax.hbinop =
  | HAdd
  | HSub
  | HMul
  | HDiv
[@@deriving yojson]

type hbool_binop = Core_syntax.hbool_binop =
  | HAnd
  | HOr
[@@deriving yojson]

type hunop = Core_syntax.hunop =
  | HNeg
  | HNot
[@@deriving yojson]

type hexpr = Core_syntax.hexpr = {
  hexpr : hexpr_desc;
  loc : loc option;
}

and hexpr_desc = Core_syntax.hexpr_desc =
  | HLitInt of int
  | HLitBool of bool
  | HVar of ident
  | HPreK of ident * int
  | HArithBin of hbinop * hexpr * hexpr
  | HBoolBin of hbool_binop * hexpr * hexpr
  | HCmp of relop * hexpr * hexpr
  | HUn of hunop * hexpr
[@@deriving yojson]

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

type ltl_o = Core_syntax.ltl_o = { value : ltl; oid : int; loc : loc option } [@@deriving yojson]
type vdecl = Core_syntax.vdecl = { vname : ident; vty : ty } [@@deriving yojson]
type invariant_state_rel = { state : ident; formula : Fo_formula.t } [@@deriving yojson]

type stmt = { stmt : stmt_desc; loc : loc option }

and stmt_desc =
  | SAssign of ident * iexpr
  | SIf of iexpr * stmt list * stmt list
  | SMatch of iexpr * (ident * stmt list) list * stmt list
  | SSkip
  | SCall of ident * iexpr list * ident list
[@@deriving yojson]

type transition = {
  src : ident;
  dst : ident;
  guard : iexpr option;
  body : stmt list;
}


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


type node_specification = {
  spec_assumes : ltl list;
  spec_guarantees : ltl list;
  spec_invariants_state_rel : invariant_state_rel list;
}


type node = {
  semantics : node_semantics;
  specification : node_specification;
}


type program = node list

let semantics_of_node (n : node) : node_semantics =
  n.semantics

let specification_of_node (n : node) : node_specification =
  n.specification
