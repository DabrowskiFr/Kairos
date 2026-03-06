Require Import core.CoreStepSig.
Require Import obligations.ObligationGenSig.
Require Import obligations.OracleSig.

Set Implicit Arguments.

Module Type ORACLE_SEM_SIG
  (C : CORE_STEP_SIG)
  (E : OBLIGATION_GEN_SIG with Definition StepCtx := C.StepCtx).

  Include ORACLE_SIG E.

  Axiom obligation_valid_pointwise :
    forall (obl : E.Obligation) u k,
      ObligationValid obl ->
      obl (C.ctx_at u k).
End ORACLE_SEM_SIG.
