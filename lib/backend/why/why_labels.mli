(*---------------------------------------------------------------------------*)

[@@@ocaml.warning "-8-26-27-32-33"]

(** Normalize a human label into a stable Why3‑friendly form. *)
val normalize_label : string -> string
(** Encode a label as an attribute string payload. *)
val attr_string : string -> string
(** Build a Why3 attribute for a given label. *)
val attr_for_label : string -> Why3.Ident.attribute
(** Extract a label from a set of Why3 attributes (if present). *)
val label_of_attrs : Why3.Ident.Sattr.t -> string option
