module type S = sig
  type formula

  val shift_one_tick : formula -> formula
end
