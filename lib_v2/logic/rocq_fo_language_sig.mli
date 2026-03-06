(** OCaml mirror of Rocq [logic/FOLanguageSig]. *)

module type S = sig
  type formula
  type history

  val eval : history -> formula -> bool
end
