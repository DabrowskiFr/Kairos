From Kairos.core Require Import CoreStepSig.
From Kairos.obligations Require Import ObligationGenSig.
From Kairos.obligations Require Import OracleSemSig.

Set Implicit Arguments.

Module Type HOARE_TASK_GEN_SIG
  (C : CORE_STEP_SIG)
  (E : OBLIGATION_GEN_SIG with Definition StepCtx := C.StepCtx).

  Parameter HoareTriple : Type.

  (* Derived by the formalized core from generated clauses. *)
  Parameter encode_clause : E.Clause -> HoareTriple.

  Parameter HoareValid : HoareTriple -> Prop.

  (* Semantic adequacy of the encoding. *)
  Axiom hoare_valid_implies_clause_pointwise :
    forall (cl : E.Clause) u k,
      HoareValid (encode_clause cl) ->
      cl (C.ctx_at u k).
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
    forall cl, E.Generated cl -> check (H.encode_clause cl) = true.
End EXTERNAL_VC_TOOL_SIG.

Module MakeOracleSemFromHoareTool
  (C : CORE_STEP_SIG)
  (E : OBLIGATION_GEN_SIG with Definition StepCtx := C.StepCtx)
  (H : HOARE_TASK_GEN_SIG C E)
  (X : EXTERNAL_VC_TOOL_SIG C E H)
  <: ORACLE_SEM_SIG C E.

  Definition Oracle (cl : E.Clause) : bool :=
    X.check (H.encode_clause cl).

  Definition ClauseValid (cl : E.Clause) : Prop :=
    H.HoareValid (H.encode_clause cl).

  Theorem Oracle_sound :
    forall cl, Oracle cl = true -> ClauseValid cl.
  Proof.
    intros cl Hyes.
    unfold Oracle, ClauseValid.
    exact (X.check_sound (t := H.encode_clause cl) Hyes).
  Qed.

  Theorem Oracle_complete :
    forall cl, E.Generated cl -> Oracle cl = true.
  Proof.
    intros cl Hgen.
    unfold Oracle.
    exact (X.check_complete_generated (cl := cl) Hgen).
  Qed.

  Theorem clause_valid_pointwise :
    forall (cl : E.Clause) u k,
      ClauseValid cl ->
      cl (C.ctx_at u k).
  Proof.
    intros cl u k Hvalid.
    unfold ClauseValid in Hvalid.
    exact (@H.hoare_valid_implies_clause_pointwise cl u k Hvalid).
  Qed.
End MakeOracleSemFromHoareTool.
