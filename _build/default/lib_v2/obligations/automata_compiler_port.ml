module type S = sig
  type formula
  type automata_bundle

  val compile : assumes:formula list -> guarantees:formula list -> automata_bundle
end
