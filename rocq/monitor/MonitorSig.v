Set Implicit Arguments.

Module Type MONITOR_SIG.
  Parameter Obs : Type.
  Definition stream (A : Type) : Type := nat -> A.

  Parameter Q : Type.
  Parameter q0 : Q.
  Parameter bad : Q.
  Parameter delta : Q -> Obs -> Q.

  Fixpoint state_at (w : stream Obs) (k : nat) : Q :=
    match k with
    | O => q0
    | S n => delta (state_at w n) (w n)
    end.

  Definition avoids_bad (w : stream Obs) : Prop :=
    forall k, state_at w k <> bad.
End MONITOR_SIG.

