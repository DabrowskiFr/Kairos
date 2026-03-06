Require Import core.CoreStepSig.
Require Import obligations.ObligationGenSig.
Require Import obligations.OracleSemSig.

Set Implicit Arguments.

Module Type HOARE_TASK_GEN_SIG
  (C : CORE_STEP_SIG)
  (E : OBLIGATION_GEN_SIG with Definition StepCtx := C.StepCtx).

  Parameter HoareTriple : Type.

  (* Derived by the formalized core from generated obligations. *)
  Parameter encode_obligation : E.Obligation -> HoareTriple.

  Parameter HoareValid : HoareTriple -> Prop.

  (* Semantic adequacy of the encoding. *)
  Axiom hoare_valid_implies_obligation_pointwise :
    forall (obl : E.Obligation) u k,
      HoareValid (encode_obligation obl) ->
      obl (C.ctx_at u k).
End HOARE_TASK_GEN_SIG.

Module Type EXTERNAL_VC_TOOL_SIG
  (C : CORE_STEP_SIG)
  (E : OBLIGATION_GEN_SIG with Definition StepCtx := C.StepCtx)
  (H : HOARE_TASK_GEN_SIG C E).

  Parameter check : H.HoareTriple -> bool.

  (* External checker correction hypothesis. *)
  Axiom check_sound :
    forall t, check t = true -> H.HoareValid t.

  (* Completeness required by current conditional-correctness chain. *)
  Axiom check_complete_generated :
    forall obl, E.Generated obl -> check (H.encode_obligation obl) = true.
End EXTERNAL_VC_TOOL_SIG.

Module MakeOracleSemFromHoareTool
  (C : CORE_STEP_SIG)
  (E : OBLIGATION_GEN_SIG with Definition StepCtx := C.StepCtx)
  (H : HOARE_TASK_GEN_SIG C E)
  (X : EXTERNAL_VC_TOOL_SIG C E H)
  <: ORACLE_SEM_SIG C E.

  Definition Oracle (obl : E.Obligation) : bool :=
    X.check (H.encode_obligation obl).

  Definition ObligationValid (obl : E.Obligation) : Prop :=
    H.HoareValid (H.encode_obligation obl).

  Theorem Oracle_sound :
    forall obl, Oracle obl = true -> ObligationValid obl.
  Proof.
    intros obl Hyes.
    unfold Oracle, ObligationValid.
    exact (X.check_sound (t := H.encode_obligation obl) Hyes).
  Qed.

  Theorem Oracle_complete :
    forall obl, E.Generated obl -> Oracle obl = true.
  Proof.
    intros obl Hgen.
    unfold Oracle.
    exact (X.check_complete_generated (obl := obl) Hgen).
  Qed.

  Theorem obligation_valid_pointwise :
    forall (obl : E.Obligation) u k,
      ObligationValid obl ->
      obl (C.ctx_at u k).
  Proof.
    intros obl u k Hvalid.
    unfold ObligationValid in Hvalid.
    exact (@H.hoare_valid_implies_obligation_pointwise obl u k Hvalid).
  Qed.
End MakeOracleSemFromHoareTool.
