(*---------------------------------------------------------------------------*)

[@@@ocaml.warning "-8-26-27-32-33"]

val normalize_label : string -> string
val attr_string : string -> string
val attr_for_label : string -> Why3.Ident.attribute
val label_of_attrs : Why3.Ident.Sattr.t -> string option
