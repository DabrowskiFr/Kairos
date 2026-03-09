Set Implicit Arguments.

Module Type CORE_STEP_SIG.
  Parameter InputVal OutputVal Mem Ctrl : Type.
  Definition stream (A : Type) : Type := nat -> A.

  Parameter StepCtx : Type.
  Parameter init_ctrl : Ctrl.
  Parameter init_mem : Mem.

  Parameter step : Ctrl -> Mem -> InputVal -> Ctrl * Mem * OutputVal.
  Parameter cfg_at : stream InputVal -> nat -> Ctrl * Mem.
  Parameter ctx_at : stream InputVal -> nat -> StepCtx.
  Parameter run_trace : stream InputVal -> stream (InputVal * OutputVal).
End CORE_STEP_SIG.

