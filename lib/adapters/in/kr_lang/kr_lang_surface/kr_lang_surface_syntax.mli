(** Surface AST produced directly by the parser.

    It preserves user-facing conveniences such as indexed declarations, finite
    quantifiers, specification definitions, observers, history aliases and
    finite quantifiers and history aliases. [Ast] combines these
    pieces into complete declarations, statements and nodes. *)

open Kr_lang_shared.Kr_lang_shared_syntax
open Kr_lang_core.Kr_lang_core_syntax
include module type of Kr_lang_shared.Kr_lang_shared_syntax

type indexed_ref = {
  ref_base : ident;
  ref_indices : ident list;
}
[@@deriving yojson]
(** Variable reference whose symbolic indices have not yet been flattened. *)

type raw_vdecl = {
  raw_vname : ident;
  raw_indices : ident list list option;
  raw_vty : ty;
}
[@@deriving yojson]
(** Possibly indexed variable declaration. Each index dimension is expanded
    during elaboration. *)

type typed_param = {
  param_name : ident;
  param_ty : ty;
}
[@@deriving yojson]
(** Typed parameter of a surface predicate. *)

type method_param_mode = Kr_domain_core.Kr_domain_core_syntax.method_param_mode = MPIn | MPInOut
[@@deriving yojson]
(** Whether a method parameter is read-only or may be updated. *)

type method_param = Kr_domain_core.Kr_domain_core_syntax.method_param = {
  method_param_name : ident;
  method_param_ty : ty;
  method_param_mode : method_param_mode;
}
[@@deriving yojson]
(** Method parameter before indexed declarations are expanded. *)

type spec_param_kind = SPFormula | SPHExpr | SPNat [@@deriving yojson]
(** Sort of an argument accepted by a reusable specification. *)

type nat_expr = SNNat of int | SNVar of ident [@@deriving yojson]
(** Natural literal or natural-valued specification parameter. *)

type spec_param = {
  spec_param_name : ident;
  spec_param_kind : spec_param_kind;
}
[@@deriving yojson]
(** Formal parameter of a reusable specification. *)

type expr = {
  sexpr : expr_desc;
  loc : Kr_lang_shared.Kr_lang_shared_syntax.loc option;
}

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
(** Executable surface expression. [SEPre] is permitted only in observer code
    and is eliminated into a generated delay variable. *)

type hexpr = {
  shexpr : hexpr_desc;
  hloc : Kr_lang_shared.Kr_lang_shared_syntax.loc option;
}

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
(** Logical surface expression, including history operators and finite
    quantifiers that elaboration expands. *)

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

and spec_arg = SAFormula of ltl | SAHExpr of hexpr
[@@deriving yojson]
(** Temporal surface formula and the mutually recursive arguments passed to
    reusable specification definitions. *)

type history_expr = {
  shistory_expr : history_expr_desc;
  hvloc : loc option;
}

and history_expr_desc =
  | SHValue of hexpr
  | SHIf of hexpr * history_expr * history_expr
[@@deriving yojson]
(** Conditional logical expression used by history-related surface constructs. *)

val mk_indexed_ref : ident -> ident list -> indexed_ref
(** Build a reference from its base and symbolic indices. *)

val mk_scalar_ref : ident -> indexed_ref
(** Build an unindexed reference. *)

val mk_history_expr : ?loc:loc -> history_expr_desc -> history_expr
(** Build a conditional history expression with an optional location. *)

val mk_expr : ?loc:loc -> expr_desc -> expr
(** Build an executable surface expression with an optional location. *)

val mk_hexpr : ?loc:loc -> hexpr_desc -> hexpr
(** Build a logical surface expression with an optional location. *)
