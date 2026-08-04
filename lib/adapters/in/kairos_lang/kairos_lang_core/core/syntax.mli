(** Syntax shared by the elaborated frontend AST and the final translation to
    the verification model.

    Unlike [Surface.Syntax], this layer contains no indexed declarations,
    finite quantifiers or other surface conveniences. It still distinguishes
    executable expressions from historical expressions used in logic. *)

open Kairos_lang_shared
include module type of Shared.Syntax

type expr = {
  expr : expr_desc;
  loc : loc option;
}

and expr_desc =
  | ELitInt of int
  | ELitBool of bool
  | EVar of ident
  | EFunCall of ident * expr list
  | EBin of binop * expr * expr
  | ECmp of relop * expr * expr
  | EUn of unop * expr
[@@deriving yojson]
(** Executable expression used in guards and statements. It cannot refer to
    past values. *)

type hexpr = {
  hexpr : hexpr_desc;
  loc : loc option;
}

and hexpr_desc =
  | HLitInt of int
  | HLitBool of bool
  | HVar of ident
  | HOld of hexpr
  | HPreK of ident * int
  | HPred of ident * hexpr list
  | HFunCall of ident * hexpr list
  | HBin of binop * hexpr * hexpr
  | HCmp of relop * hexpr * hexpr
  | HUn of unop * hexpr
[@@deriving yojson]
(** First-order logical expression. [HPreK (x, k)] denotes the value of [x]
    [k] instants in the past; [HOld] is reserved for method contracts. *)

type ltl_atom = hexpr * relop * hexpr [@@deriving yojson]
(** Atomic temporal proposition. *)

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
(** Temporal formulas in the safety-oriented fragment supported by Kairos. *)

type ltl_o = {
  value : ltl;
  oid : int;
  loc : loc option;
}
[@@deriving yojson]
(** Temporal formula carrying a stable identifier and source location. *)

type vdecl = Core_syntax.vdecl = {
  vname : ident;
  vty : ty;
}
[@@deriving yojson]
(** Scalar typed variable declaration. *)

type pure_function_decl = {
  function_name : ident;
  function_params : vdecl list;
  function_return : ty;
  function_requires : hexpr list;
  function_ensures : hexpr list;
  function_body : expr;
}
[@@deriving yojson]
(** Global pure function. Its contracts are non-temporal; [result] denotes the
    returned value in postconditions. *)
