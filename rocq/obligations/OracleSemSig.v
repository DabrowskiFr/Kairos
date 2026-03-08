From Kairos.core Require Import CoreStepSig.
From Kairos.obligations Require Import ObligationGenSig.
From Kairos.obligations Require Import OracleSig.

Set Implicit Arguments.

(* Historical filename kept for compatibility.

   Preferred reading/API:
   - module type [VALIDATION_SEM_SIG]

   Legacy compatibility alias:
   - module type [ORACLE_SEM_SIG] *)

Module Type ORACLE_SEM_SIG
  (C : CORE_STEP_SIG)
  (E : OBLIGATION_GEN_SIG with Definition StepCtx := C.StepCtx).

  Include ORACLE_SIG E.

  Axiom clause_valid_pointwise :
    forall (cl : E.Clause) u k,
      ClauseValid cl ->
      cl (C.ctx_at u k).
End ORACLE_SEM_SIG.

Module Type VALIDATION_SEM_SIG
  (C : CORE_STEP_SIG)
  (E : OBLIGATION_GEN_SIG with Definition StepCtx := C.StepCtx).
  Include ORACLE_SEM_SIG C E.
End VALIDATION_SEM_SIG.
