From Kairos.core Require Import CoreStepSig.
From Kairos.obligations Require Import ObligationGenSig.
From Kairos.obligations Require Import OracleSemSig.

Set Implicit Arguments.

Module Type IMPLEMENTATION_VALIDATOR_SIG
  (C : CORE_STEP_SIG)
  (E : OBLIGATION_GEN_SIG with Definition StepCtx := C.StepCtx).

  Parameter Validator : E.Clause -> bool.
  Parameter ClauseValid : E.Clause -> Prop.

  (* "Yes" is semantically sound. *)
  Axiom validator_sound_true :
    forall cl, Validator cl = true -> ClauseValid cl.

  (* If semantically valid, validator answers yes. *)
  Axiom validator_complete_valid :
    forall cl, ClauseValid cl -> Validator cl = true.

  (* Generated clauses must be accepted by the validator. *)
  Axiom validator_complete_generated :
    forall cl, E.Generated cl -> Validator cl = true.

  Axiom clause_valid_pointwise :
    forall (cl : E.Clause) u k,
      ClauseValid cl ->
      cl (C.ctx_at u k).
End IMPLEMENTATION_VALIDATOR_SIG.

Module MakeOracleSemFromValidator
  (C : CORE_STEP_SIG)
  (E : OBLIGATION_GEN_SIG with Definition StepCtx := C.StepCtx)
  (V : IMPLEMENTATION_VALIDATOR_SIG C E)
  <: ORACLE_SEM_SIG C E.

  Definition Oracle : E.Clause -> bool := V.Validator.
  Definition ClauseValid : E.Clause -> Prop := V.ClauseValid.

  Theorem Oracle_sound :
    forall cl, Oracle cl = true -> ClauseValid cl.
  Proof.
    intros cl H.
    exact (V.validator_sound_true (cl := cl) H).
  Qed.

  Theorem Oracle_complete :
    forall cl, E.Generated cl -> Oracle cl = true.
  Proof.
    intros cl Hgen.
    exact (V.validator_complete_generated (cl := cl) Hgen).
  Qed.

  Theorem clause_valid_pointwise :
    forall (cl : E.Clause) u k,
      ClauseValid cl ->
      cl (C.ctx_at u k).
  Proof.
    intros cl u k Hvalid.
    exact (@V.clause_valid_pointwise cl u k Hvalid).
  Qed.
End MakeOracleSemFromValidator.
