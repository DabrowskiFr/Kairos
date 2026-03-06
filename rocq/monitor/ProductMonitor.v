Require Import core.CoreStepSig.
Require Import monitor.MonitorSig.

Set Implicit Arguments.

Module Type PRODUCT_MONITOR_SIG
  (C : CORE_STEP_SIG)
  (A : MONITOR_SIG with Definition Obs := C.InputVal)
  (G : MONITOR_SIG with Definition Obs := (C.InputVal * C.OutputVal)%type).

  Definition ProductState : Type := C.Ctrl * A.Q * G.Q.
  Definition proj_ctrl (ps : ProductState) : C.Ctrl := let '(c, _, _) := ps in c.
  Definition proj_a (ps : ProductState) : A.Q := let '(_, qa, _) := ps in qa.
  Definition proj_g (ps : ProductState) : G.Q := let '(_, _, qg) := ps in qg.

  Parameter product_state_at : C.stream C.InputVal -> nat -> ProductState.

  Axiom proj_A_matches :
    forall u k,
      proj_a (product_state_at u k) = A.state_at u k.

  Axiom proj_G_matches :
    forall u k,
      proj_g (product_state_at u k) = G.state_at (C.run_trace u) k.
End PRODUCT_MONITOR_SIG.
