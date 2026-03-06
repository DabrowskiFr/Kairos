(** Externalized validation layer boundary. *)

module type EXTERNAL_VALIDATION = sig
  type triple

  val check : triple -> bool
end
