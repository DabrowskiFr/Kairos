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

(** Surface syntax produced by the parser.

    This AST intentionally keeps frontend conveniences explicit: indexed
    variable names, bounded quantifiers over enum types, local predicates, spec
    definitions, inline actions, history aliases, and statement-level [for]
    loops. [Kx_elaborate] is the only module that lowers this syntax into the
    smaller [Kx_ast] consumed by the rest of Kairos. *)

open Kx_core_syntax

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

type expr = { sexpr : expr_desc; loc : Kx_loc.loc option }

and expr_desc =
  | SELitInt of int
  | SELitBool of bool
  | SEVar of indexed_ref
  | SECall of ident * expr list
  | SEBin of binop * expr * expr
  | SECmp of relop * expr * expr
  | SEUn of unop * expr
[@@deriving yojson]

type hexpr = { shexpr : hexpr_desc; hloc : Kx_loc.loc option }

and hexpr_desc =
  | SHLitInt of int
  | SHLitBool of bool
  | SHVar of indexed_ref
  | SHPreK of indexed_ref * nat_expr
  | SHPast of hexpr * nat_expr
  | SHHistoryCall of ident * indexed_ref
  | SHHistoryAlias of ident * indexed_ref
  | SHCall of ident * ident list
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

type function_decl = {
  function_name : ident;
  function_params : raw_vdecl list;
  function_return : ty;
  function_requires : hexpr list;
  function_ensures : hexpr list;
  function_body : expr;
}
[@@deriving yojson]

type history_alias_decl = {
  alias_name : ident;
  alias_param : ident;
  alias_rhs_param : ident;
  alias_k : int;
}
[@@deriving yojson]

type predicate_decl = {
  predicate_name : ident;
  predicate_params : ident list;
  predicate_body : hexpr;
}
[@@deriving yojson]

type stmt = { sstmt : stmt_desc; sloc : Kx_loc.loc option }

and stmt_desc =
  | SSAssign of indexed_ref * expr
  | SSIf of expr * stmt list * stmt list
  | SSMatch of expr * (ident * stmt list) list * stmt list
  | SSSkip
  | SSCall of ident * expr list * ident list
  | SSActionCall of ident * ident list
  | SSFor of ident * ident * stmt list
[@@deriving yojson]

type history_expr = { shistory_expr : history_expr_desc; hvloc : Kx_loc.loc option }

and history_expr_desc =
  | SHValue of hexpr
  | SHIf of hexpr * history_expr * history_expr
[@@deriving yojson]

type action_decl = {
  action_name : ident;
  action_params : ident list;
  action_body : stmt list;
}
[@@deriving yojson]

type spec_def_decl = {
  spec_def_name : ident;
  spec_def_params : spec_param list;
  spec_def_body : ltl;
}
[@@deriving yojson]

type history_def_decl = {
  history_def_name : ident;
  history_param : ident;
  history_ty : ty;
  history_init : history_expr;
  history_init_ensures : hexpr list;
  history_step : history_expr;
  history_step_ensures : hexpr list;
}
[@@deriving yojson]

type observer_decl = {
  observer_name : ident;
  observer_ty : ty;
  observer_init : stmt list;
  observer_step : stmt list;
}
[@@deriving yojson]

type contract_item =
  | SCRequires of ltl
  | SCEnsures of ltl
[@@deriving yojson]

type state_invariant = {
  state : ident;
  formula : hexpr;
}
[@@deriving yojson]

type transition = {
  src : ident;
  dst : ident;
  guard : expr option;
  body : stmt list;
  ensures : hexpr list;
}
[@@deriving yojson]

type state_decls = {
  states : ident list;
  init_state : ident;
}
[@@deriving yojson]

type node = {
  node_name : ident;
  inputs : raw_vdecl list;
  outputs : raw_vdecl list;
  history_aliases : history_alias_decl list;
  ghosts : raw_vdecl list;
  observers : observer_decl list;
  predicates : predicate_decl list;
  actions : action_decl list;
  contracts : contract_item list;
  instances : (ident * ident) list;
  locals : raw_vdecl list;
  state_decls : state_decls;
  state_invariants : state_invariant list;
  transitions : transition list;
}
[@@deriving yojson]

type frontend_decl =
  | STypeDecl of enum_decl
  | SFunctionDecl of function_decl
  | SSpecDefDecl of spec_def_decl
  | SHistoryDefDecl of history_def_decl
[@@deriving yojson]

type import_decl = string * Kx_loc.loc option [@@deriving yojson]

type source = {
  imports : import_decl list;
  frontend_decls : frontend_decl list;
  nodes : node list;
}
[@@deriving yojson]

type program = node list [@@deriving yojson]

let mk_indexed_ref ref_base ref_indices = { ref_base; ref_indices }
let mk_scalar_ref ref_base = mk_indexed_ref ref_base []
let mk_history_expr ?loc shistory_expr = { shistory_expr; hvloc = loc }

let mk_expr ?loc sexpr = { sexpr; loc }
let mk_hexpr ?loc shexpr = { shexpr; hloc = loc }
let mk_stmt ?loc sstmt = { sstmt; sloc = loc }
