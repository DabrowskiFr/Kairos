module type S = sig
  type obc_program
  type obligation

  val augment : obc_program -> obligation list -> obc_program
end
