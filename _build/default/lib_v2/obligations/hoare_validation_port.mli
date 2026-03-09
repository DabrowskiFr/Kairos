(** External port: Hoare triplets validity checker. *)

module type S = sig
  type triple

  val check : triple -> bool
end
