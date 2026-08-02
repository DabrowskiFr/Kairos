(** Location-preserving constructors for [Kx_core_syntax].

    These helpers keep elaboration code focused on transformations rather than
    repetitive record construction. *)

open Kx_core_syntax

val mk_expr : ?loc:Kx_syntax_common.loc -> expr_desc -> expr
(** Build an executable expression with an optional source location. *)

val with_expr_desc : expr -> expr_desc -> expr
(** Replace an executable expression's description while preserving location. *)

val mk_var : ident -> expr
(** Build an executable variable reference without a source location. *)

val mk_int : int -> expr
(** Build an executable integer literal without a source location. *)

val mk_bool : bool -> expr
(** Build an executable Boolean literal without a source location. *)

val mk_hexpr : ?loc:Kx_syntax_common.loc -> hexpr_desc -> hexpr
(** Build a historical expression with an optional source location. *)

val with_hexpr_desc : hexpr -> hexpr_desc -> hexpr
(** Replace a historical expression's description while preserving location. *)

val mk_hvar : ident -> hexpr
(** Build a logical variable reference without a source location. *)

val mk_hint : int -> hexpr
(** Build a logical integer literal without a source location. *)

val mk_hbool : bool -> hexpr
(** Build a logical Boolean literal without a source location. *)

val mk_hpre_k : ident -> int -> hexpr
(** Build a logical read of a variable at a fixed past offset. *)

val mk_hpred : ident -> hexpr list -> hexpr
(** Build a logical predicate application. *)

val mk_hnot : hexpr -> hexpr
(** Build a logical negation. *)

val mk_hand : hexpr -> hexpr -> hexpr
(** Build a logical conjunction. *)

val mk_hor : hexpr -> hexpr -> hexpr
(** Build a logical disjunction. *)

val mk_himp : hexpr -> hexpr -> hexpr
(** Build implication from negation and disjunction. *)

val hexpr_of_expr : expr -> hexpr
(** Embed an executable expression into the historical-expression layer while
    preserving its locations. *)
