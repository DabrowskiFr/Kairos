(** Optional host logging hooks. The standalone adapter is silent by default. *)

val set_handlers :
  progress:(string -> unit) -> warning:(string -> unit) -> unit

val progress : string -> unit
val warning : string -> unit
