Require Import core.CoreStepSig.
Require Import obligations.ObligationGenSig.
Require Import obligations.OracleSemSig.

Set Implicit Arguments.

Module Type IMPLEMENTATION_VALIDATOR_SIG
  (C : CORE_STEP_SIG)
  (E : OBLIGATION_GEN_SIG with Definition StepCtx := C.StepCtx).

  Parameter Validator : E.Obligation -> bool.
  Parameter ObligationValid : E.Obligation -> Prop.

  (* "Yes" is semantically sound. *)
  Axiom validator_sound_true :
    forall obl, Validator obl = true -> ObligationValid obl.

  (* If semantically valid, validator answers yes. *)
  Axiom validator_complete_valid :
    forall obl, ObligationValid obl -> Validator obl = true.

  (* Generated obligations must be accepted by the validator. *)
  Axiom validator_complete_generated :
    forall obl, E.Generated obl -> Validator obl = true.

  Axiom obligation_valid_pointwise :
    forall (obl : E.Obligation) u k,
      ObligationValid obl ->
      obl (C.ctx_at u k).
End IMPLEMENTATION_VALIDATOR_SIG.

Module MakeOracleSemFromValidator
  (C : CORE_STEP_SIG)
  (E : OBLIGATION_GEN_SIG with Definition StepCtx := C.StepCtx)
  (V : IMPLEMENTATION_VALIDATOR_SIG C E)
  <: ORACLE_SEM_SIG C E.

  Definition Oracle : E.Obligation -> bool := V.Validator.
  Definition ObligationValid : E.Obligation -> Prop := V.ObligationValid.

  Theorem Oracle_sound :
    forall obl, Oracle obl = true -> ObligationValid obl.
  Proof.
    intros obl H.
    exact (V.validator_sound_true (obl := obl) H).
  Qed.

  Theorem Oracle_complete :
    forall obl, E.Generated obl -> Oracle obl = true.
  Proof.
    intros obl Hgen.
    exact (V.validator_complete_generated (obl := obl) Hgen).
  Qed.

  Theorem obligation_valid_pointwise :
    forall (obl : E.Obligation) u k,
      ObligationValid obl ->
      obl (C.ctx_at u k).
  Proof.
    intros obl u k Hvalid.
    exact (@V.obligation_valid_pointwise obl u k Hvalid).
  Qed.
End MakeOracleSemFromValidator.
