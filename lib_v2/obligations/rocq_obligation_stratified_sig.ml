open Rocq_obligation_taxonomy_sig

module type S = sig
  type obligation

  val phase_order : role -> int
  val sorted : obligation list -> obligation list
end
