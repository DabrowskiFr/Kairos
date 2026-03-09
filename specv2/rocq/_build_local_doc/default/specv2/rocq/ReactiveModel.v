From Stdlib Require Import Arith Lia.

Set Implicit Arguments.

(** * Reactive Programs And Executions

    This module provides the semantic core used by the whole development.

    The main design choice is that a reactive program is total at the level of
    one synchronous tick by construction: [select] chooses the transition taken
    at the current tick, and [select_enabled] proves that this chosen
    transition is enabled. This avoids carrying a separate basic well-formedness
    predicate later in the theory. *)

Definition stream (A : Type) := nat -> A.

(** [ReactiveProgram] is an extensional description of a synchronous reactive
    program.

    - [ProgState], [ProgMem], [ProgInput], [ProgOutput], and [ProgTransition]
      are the semantic domains.
    - [init_state] is the initial control state.
    - [select] chooses the transition taken at a tick.
    - [enabled] is the semantic guard relation.
    - [dst_state], [upd_mem], and [out_val] describe the effect of the selected
      transition.

    The theorem [select_enabled] internalizes the totality of one tick. *)
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

  (** [cfg_from m0 u k] is the concrete configuration reached after [k] ticks
      from initial memory [m0] on input stream [u]. The configuration stores
      both the control state and the memory because both evolve across ticks. *)
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

  (** Current control state extracted from the concrete configuration. *)
  Definition state_from
      (m0 : ProgMem P)
      (u : stream (ProgInput P))
      (k : nat)
      : ProgState P :=
    fst (cfg_from m0 u k).

  (** Current memory extracted from the concrete configuration. *)
  Definition mem_from
      (m0 : ProgMem P)
      (u : stream (ProgInput P))
      (k : nat)
      : ProgMem P :=
    snd (cfg_from m0 u k).

  (** Transition selected at tick [k] from the current concrete configuration. *)
  Definition trans_from
      (m0 : ProgMem P)
      (u : stream (ProgInput P))
      (k : nat)
      : ProgTransition P :=
    let '(s, m) := cfg_from m0 u k in
    select P s m (u k).

  (** Output emitted at tick [k]. *)
  Definition out_from
      (m0 : ProgMem P)
      (u : stream (ProgInput P))
      (k : nat)
      : ProgOutput P :=
    let '(s, m) := cfg_from m0 u k in
    let t := select P s m (u k) in
    out_val P t m (u k).

  (** The next lemmas are the basic unfolding facts used everywhere else to
      reason about runs one tick at a time. *)
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
