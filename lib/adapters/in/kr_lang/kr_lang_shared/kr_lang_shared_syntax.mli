(** Vocabulary shared by the surface and core syntax trees.

    Source locations, identifiers, types and operators have the same meaning on
    both sides of elaboration, so they are defined once here. This module does
    not contain expressions or program structure. *)

type loc = Kr_domain_core.Kr_domain_core_locations.loc = {
  line : int; (** One-based start line. *)
  col : int; (** Zero-based start column, in Unicode code points. *)
  line_end : int; (** One-based end line. *)
  col_end : int; (** Zero-based end column, in Unicode code points. *)
}
[@@deriving yojson]
(** Source span attached to parsed and elaborated syntax. *)

val loc_of_positions : Lexing.position -> Lexing.position -> loc
(** Build a source span from Sedlex/Menhir positions expressed in Unicode code
    points. *)

type ident = Kr_domain_core.Kr_domain_core_syntax.ident [@@deriving yojson]
(** Names of variables, states and declarations. *)

type ty = Kr_domain_core.Kr_domain_core_syntax.ty = TInt | TBool | TReal | TCustom of string
[@@deriving yojson]
(** Types accepted by the Kairos frontend. *)

type enum_decl = Kr_domain_core.Kr_domain_core_syntax.enum_decl = {
  enum_name : ident;
  enum_constructors : ident list;
}
[@@deriving yojson]
(** Finite enumeration declaration shared unchanged across elaboration. *)

type binop = Kr_domain_core.Kr_domain_core_syntax.binop = Add | Sub | Mul | Div | And | Or
[@@deriving yojson]
(** Arithmetic and Boolean binary operators. *)

type unop = Kr_domain_core.Kr_domain_core_syntax.unop = Neg | Not [@@deriving yojson]
(** Arithmetic and Boolean unary operators. *)

type relop = Kr_domain_core.Kr_domain_core_syntax.relop = REq | RNeq | RLt | RLe | RGt | RGe
[@@deriving yojson]
(** Equality and ordering operators. *)
