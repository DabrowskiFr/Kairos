(** Backend-neutral obligation export from a versioned WhyML request. *)

val run :
  Kairos_proof_contract.Proof_backend_contract.request ->
  Kairos_proof_contract.Proof_backend_contract.response
