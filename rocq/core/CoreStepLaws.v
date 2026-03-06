Require Import core.CoreStepSig.

Set Implicit Arguments.

Module Type CORE_STEP_LAWS_SIG (C : CORE_STEP_SIG).
  Axiom cfg_at_0 :
    forall u, C.cfg_at u O = (C.init_ctrl, C.init_mem).

  Axiom cfg_at_S :
    forall u k,
      let '(c, m) := C.cfg_at u k in
      let '(c', m', _o) := C.step c m (u k) in
      C.cfg_at u (S k) = (c', m').
End CORE_STEP_LAWS_SIG.

