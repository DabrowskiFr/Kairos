module type S = sig
  type formula
  type history

  val eval : history -> formula -> bool
end
