(** Source location primitives shared by frontend and diagnostics.

    A location records one half-open span in line/column coordinates. *)

(** Source span with one-based lines and zero-based Unicode columns. *)
type loc = { line : int; col : int; line_end : int; col_end : int } [@@deriving yojson]
