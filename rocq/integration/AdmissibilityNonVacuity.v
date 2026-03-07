Require Import integration.ThreeLayerArchitecture.

Set Implicit Arguments.

Module Type NON_VACUITY_SIG (P : PROGRAM_LAYER_SIG).
  Parameter witness_input : nat -> P.InputVal.
  Axiom witness_is_admissible : P.AvoidA witness_input.
End NON_VACUITY_SIG.

Module MakeThreeLayerCorrectnessWithWitness
  (P : PROGRAM_LAYER_SIG)
  (K : KAIROS_CORE_LAYER_SIG P)
  (S : VALIDATION_LAYER_SIG P K)
  (NV : NON_VACUITY_SIG P).

  Module Corr := MakeThreeLayerCorrectness P K S.

  Theorem exists_admissible_input : exists u, P.AvoidA u.
  Proof.
    exists NV.witness_input.
    exact NV.witness_is_admissible.
  Qed.

  Theorem exists_trace_satisfying_guarantee :
    exists u, P.AvoidG (P.run_trace u).
  Proof.
    exists NV.witness_input.
    apply Corr.validation_conditional_correctness_three_layers.
    exact NV.witness_is_admissible.
  Qed.
End MakeThreeLayerCorrectnessWithWitness.
