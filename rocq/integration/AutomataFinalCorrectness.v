From Stdlib Require Import Logic.Classical.

Require Import integration.ThreeLayerArchitecture.
Require Import integration.ThreeLayerFromCore.
Require Import interfaces.ExternalValidationAssumptions.

Set Implicit Arguments.

Module MakeAutomataFinalCorrectness
  (P : PROGRAM_LAYER_SIG)
  (K : KAIROS_CORE_FROM_PROVED_SIG P)
  (X : EXTERNAL_VALIDATION_ASSUMPTIONS P K).

  Theorem automata_program_correctness :
    forall u,
      P.AvoidA u ->
      P.AvoidG (P.run_trace u).
  Proof.
    intros u HA.
    destruct (classic (P.AvoidG (P.run_trace u))) as [HG | HnG].
    - exact HG.
    - destruct (K.bad_local_step_if_G_violated (u := u) HA HnG) as [k Hbad].
      destruct (K.generation_coverage_from_bad_local_step (u := u) (k := k) Hbad)
        as [cl [Hgen Hnot]].
      pose proof (X.oracle_complete_generated (cl := cl) Hgen) as Hor.
      pose proof (X.oracle_sound_true (cl := cl) u k Hor) as Hholds.
      exfalso.
      apply Hnot.
      exact Hholds.
  Qed.
End MakeAutomataFinalCorrectness.
