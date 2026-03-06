module type S = sig
  type obligation

  val obligation_valid : obligation -> bool
end
