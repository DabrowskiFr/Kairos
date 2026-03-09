(** OCaml mirror of Rocq [obligations/ObligationGenSig]. *)

module type S = sig
  type program
  type obligation

  val generate : program -> obligation list
end
