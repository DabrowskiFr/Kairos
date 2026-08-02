(** Vocabulary shared by the surface and core syntax trees.

    Source locations, identifiers, types and operators have the same meaning on
    both sides of elaboration, so they are defined once here. This module does
    not contain expressions or program structure. *)

type loc = {
  line : int; (** One-based start line. *)
  col : int; (** Zero-based start column. *)
  line_end : int; (** One-based end line. *)
  col_end : int; (** Zero-based end column. *)
}
[@@deriving yojson]
(** Source span attached to parsed and elaborated syntax. *)

type ident = string [@@deriving yojson]
(** Names of variables, states and declarations. *)

type ty = TInt | TBool | TReal | TCustom of string [@@deriving yojson]
(** Types accepted by the Kairos frontend. *)

type enum_decl = {
  enum_name : ident;
  enum_constructors : ident list;
}
[@@deriving yojson]
(** Finite enumeration declaration shared unchanged across elaboration. *)

type binop = Add | Sub | Mul | Div | And | Or [@@deriving yojson]
(** Arithmetic and Boolean binary operators. *)

type unop = Neg | Not [@@deriving yojson]
(** Arithmetic and Boolean unary operators. *)

type relop = REq | RNeq | RLt | RLe | RGt | RGe [@@deriving yojson]
(** Equality and ordering operators. *)
