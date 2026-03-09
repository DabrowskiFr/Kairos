(** OCaml mirror of Rocq [refinement/RefinementSig]. *)

module type S = sig
  type abstract_model
  type concrete_model

  val refines : concrete_model -> abstract_model -> bool
end
