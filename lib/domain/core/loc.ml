(** Source location primitives shared by frontend and diagnostics.

    A location records one half-open span in line/column coordinates. *)

(** Source span in 1-based line/column coordinates. *)
type loc = { line : int; col : int; line_end : int; col_end : int } [@@deriving yojson]
