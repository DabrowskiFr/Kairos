(** OCaml mirror of Rocq [logic/ShiftSpecSig]. *)

module type S = sig
  type formula

  val shift_one_tick : formula -> formula
end
