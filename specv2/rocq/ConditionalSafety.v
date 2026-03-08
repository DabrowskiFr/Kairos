From Stdlib Require Import Arith Classical ChoiceFacts.
From SpecV2 Require Import ReactiveModel.

Set Implicit Arguments.

Record SafetyAutomaton (X : Type) : Type := {
  AutState : Type;
  q0 : AutState;
  qbad : AutState;
  qstep : AutState -> X -> AutState;
  qeq_dec : forall x y : AutState, {x = y} + {x <> y}
}.

Section SafetyRuns.
  Context {X : Type} (A : SafetyAutomaton X).

  Fixpoint run_aut (w : stream X) (k : nat) : AutState A :=
    match k with
    | 0 => q0 A
    | S k' => qstep A (run_aut w k') (w k')
    end.

  Definition avoids_bad (w : stream X) : Prop :=
    forall k, run_aut w k <> qbad A.

  Lemma not_avoids_bad_ex_bad :
    forall w, ~ avoids_bad w -> exists n, run_aut w n = qbad A.
  Proof.
    intros w H.
    unfold avoids_bad in H.
    apply Classical_Pred_Type.not_all_ex_not in H.
    destruct H as [n Hn].
    destruct (qeq_dec A (run_aut w n) (qbad A)) as [Heq|Hneq].
    - now exists n.
    - exfalso; apply Hn; exact Hneq.
  Qed.
End SafetyRuns.

Section ConditionalSafety.
  Context (P : ReactiveProgram).

  Record ConditionalSpec : Type := {
    assume_aut : SafetyAutomaton (ProgInput P);
    guarantee_aut : SafetyAutomaton (ProgInput P * ProgOutput P);
    assume_init_not_bad : q0 assume_aut <> qbad assume_aut;
    guarantee_init_not_bad : q0 guarantee_aut <> qbad guarantee_aut
  }.

  Context (Spec : ConditionalSpec).

  Definition trace_from
      (m0 : ProgMem P)
      (u : stream (ProgInput P))
      : stream (ProgInput P * ProgOutput P) :=
    fun k => (u k, out_from P m0 u k).

  Definition assume_state_at (u : stream (ProgInput P)) (k : nat) :=
    run_aut (assume_aut Spec) u k.

  Definition guarantee_state_at
      (m0 : ProgMem P)
      (u : stream (ProgInput P))
      (k : nat) :=
    run_aut (guarantee_aut Spec) (trace_from m0 u) k.

  Definition AvoidA (u : stream (ProgInput P)) : Prop :=
    avoids_bad (assume_aut Spec) u.

  Definition AvoidG (u : stream (ProgInput P)) : Prop :=
    forall m0 : ProgMem P,
      avoids_bad (guarantee_aut Spec) (trace_from m0 u).

  Lemma bad_successor_of_not_avoidG :
    forall (m0 : ProgMem P) (u : stream (ProgInput P)),
      ~ avoids_bad (guarantee_aut Spec) (trace_from m0 u) ->
      exists k, guarantee_state_at m0 u (S k) = qbad (guarantee_aut Spec).
  Proof.
    intros m0 u Hbad.
    pose proof
      (not_avoids_bad_ex_bad
         (A := guarantee_aut Spec)
         (w := trace_from m0 u)
         Hbad)
      as [n Hn].
    destruct n.
    - exfalso.
      apply (guarantee_init_not_bad Spec).
      exact Hn.
    - exists n; exact Hn.
  Qed.
End ConditionalSafety.
