Require Import monitor.MonitorSig.

Set Implicit Arguments.

Module Type INPUT_ADMISSIBILITY_SIG (A : MONITOR_SIG).
  Definition InputOk (u : A.stream A.Obs) (k : nat) : Prop :=
    A.state_at u k <> A.bad.

  Definition AvoidA (u : A.stream A.Obs) : Prop :=
    A.avoids_bad u.

  Axiom avoid_implies_input_ok :
    forall u k, AvoidA u -> InputOk u k.
End INPUT_ADMISSIBILITY_SIG.

