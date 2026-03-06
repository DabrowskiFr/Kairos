Require Import core.CoreStepSig.

Set Implicit Arguments.

Module Type CORE_REACTIVE_LAWS_SIG (C : CORE_STEP_SIG).
  Parameter cur_ctrl : C.StepCtx -> C.Ctrl.
  Parameter cur_mem : C.StepCtx -> C.Mem.
  Parameter cur_input : C.StepCtx -> C.InputVal.
  Parameter cur_output : C.StepCtx -> C.OutputVal.

  Axiom ctx_input_is_stream :
    forall u k, cur_input (C.ctx_at u k) = u k.

  Axiom cfg_ctx_coherent :
    forall u k,
      (cur_ctrl (C.ctx_at u k), cur_mem (C.ctx_at u k)) = C.cfg_at u k.

  Axiom trace_ctx_coherent :
    forall u k,
      C.run_trace u k = (cur_input (C.ctx_at u k), cur_output (C.ctx_at u k)).
End CORE_REACTIVE_LAWS_SIG.
