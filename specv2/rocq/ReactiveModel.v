From Stdlib Require Import Arith Lia.

Set Implicit Arguments.

Definition stream (A : Type) := nat -> A.

Record ReactiveProgram : Type := {
  ProgState : Type;
  ProgMem : Type;
  ProgInput : Type;
  ProgOutput : Type;
  ProgTransition : Type;

  init_state : ProgState;

  select : ProgState -> ProgMem -> ProgInput -> ProgTransition;
  enabled : ProgTransition -> ProgState -> ProgMem -> ProgInput -> Prop;
  dst_state : ProgTransition -> ProgState -> ProgState;
  upd_mem : ProgTransition -> ProgMem -> ProgInput -> ProgMem;
  out_val : ProgTransition -> ProgMem -> ProgInput -> ProgOutput;

  select_enabled :
    forall s m i, enabled (select s m i) s m i
}.

Section Runs.
  Context (P : ReactiveProgram).

  Fixpoint cfg_from
      (m0 : ProgMem P)
      (u : stream (ProgInput P))
      (k : nat)
      : ProgState P * ProgMem P :=
    match k with
    | 0 => (init_state P, m0)
    | S k' =>
        let '(s, m) := cfg_from m0 u k' in
        let t := select P s m (u k') in
        (dst_state P t s, upd_mem P t m (u k'))
    end.

  Definition state_from
      (m0 : ProgMem P)
      (u : stream (ProgInput P))
      (k : nat)
      : ProgState P :=
    fst (cfg_from m0 u k).

  Definition mem_from
      (m0 : ProgMem P)
      (u : stream (ProgInput P))
      (k : nat)
      : ProgMem P :=
    snd (cfg_from m0 u k).

  Definition trans_from
      (m0 : ProgMem P)
      (u : stream (ProgInput P))
      (k : nat)
      : ProgTransition P :=
    let '(s, m) := cfg_from m0 u k in
    select P s m (u k).

  Definition out_from
      (m0 : ProgMem P)
      (u : stream (ProgInput P))
      (k : nat)
      : ProgOutput P :=
    let '(s, m) := cfg_from m0 u k in
    let t := select P s m (u k) in
    out_val P t m (u k).

  Lemma cfg_from_0 :
    forall m0 u,
      cfg_from m0 u 0 = (init_state P, m0).
  Proof.
    reflexivity.
  Qed.

  Lemma cfg_from_S :
    forall m0 u k,
      cfg_from m0 u (S k) =
      let '(s, m) := cfg_from m0 u k in
      let t := select P s m (u k) in
      (dst_state P t s, upd_mem P t m (u k)).
  Proof.
    reflexivity.
  Qed.

  Lemma trans_enabled_from :
    forall m0 u k,
      let '(s, m) := cfg_from m0 u k in
      enabled P (trans_from m0 u k) s m (u k).
  Proof.
    intros m0 u k.
    unfold trans_from.
    destruct (cfg_from m0 u k) as [s m].
    apply select_enabled.
  Qed.
End Runs.
