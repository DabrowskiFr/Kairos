(** Non-temporal boolean formulas over first-order atoms. *)

type t =
  | FTrue
  | FFalse
  | FAtom of Ast.fo_atom
  | FNot of t
  | FAnd of t * t
  | FOr of t * t
  | FImp of t * t
[@@deriving yojson]
