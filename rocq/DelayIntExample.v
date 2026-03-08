From Stdlib Require Import Arith.Arith.
From Stdlib Require Import Logic.FunctionalExtensionality.
Require Import KairosOracle.

Module DelayIntProof.
Module KO := KairosOracleModel.

(* This file is an execution-level sanity check for the delay example.
   It is useful as a concrete semantic companion to the main proof, but it is
   not itself the place where the abstract proof architecture should be read. *)

Definition Input : Type := nat.
Definition Output : Type := nat.
Definition Mem : Type := nat.

Inductive PState : Type :=
| SInit
| SRun.

Inductive PTrans : Type :=
| TInit
| TRun.

Definition paut : KO.ProgramAutomaton Input Output Mem PState :=
  {|
    KO.Trans := PTrans;
    KO.src_of := fun t =>
      match t with
      | TInit => SInit
      | TRun => SRun
      end;
    KO.dst_of := fun t =>
      match t with
      | TInit => SRun
      | TRun => SRun
      end;
    KO.guard_of := fun _ _ _ => True;
    KO.upd_of := fun _ _ i => i;
    KO.out_of := fun t m _ =>
      match t with
      | TInit => 0
      | TRun => m
      end;
  |}.

Definition pselect (s : PState) (_m : Mem) (_i : Input) : KO.Trans paut :=
  match s with
  | SInit => TInit
  | SRun => TRun
  end.

Lemma pselect_enabled :
  forall s m i, KO.trans_enabled paut (pselect s m i) s m i.
Proof.
  intros s m i.
  destruct s; simpl.
  - split.
    + reflexivity.
    + exact I.
  - split.
    + reflexivity.
    + exact I.
Qed.

Section RunFacts.
  Variable m0 : Mem.

  Definition cfg_at2 := KO.cfg_at paut SInit m0 pselect.
  Definition out_at2 := KO.out_at paut SInit m0 pselect.
  Definition run_trace2 := KO.run_trace paut SInit m0 pselect.

  Lemma cfg_at_succ_rf :
    forall u k, cfg_at2 u (S k) = (SRun, u k).
  Proof.
    intros u k.
    induction k as [|n IH].
    - reflexivity.
    - unfold cfg_at2 in IH |- *.
      simpl.
      remember (KO.cfg_at paut SInit m0 pselect u (S n)) as cfg eqn:Hcfg.
      destruct cfg as [s m].
      rewrite IH in Hcfg.
      inversion Hcfg; subst; clear Hcfg.
      reflexivity.
  Qed.

  Lemma out_at_0_rf :
    forall u, out_at2 u 0 = 0.
  Proof.
    intros u.
    reflexivity.
  Qed.

  Lemma out_at_succ_rf :
    forall u k, out_at2 u (S k) = u k.
  Proof.
    intros u k.
    unfold out_at2, KO.out_at, KO.out_at_from, KO.step_at, KO.step_at_from, KO.step.
    pose proof (cfg_at_succ_rf u k) as Hcfg.
    unfold cfg_at2, KO.cfg_at in Hcfg.
    rewrite Hcfg.
    reflexivity.
  Qed.

  Theorem delay_stream :
    forall u,
      out_at2 u 0 = 0 /\ forall k, out_at2 u (S k) = u k.
  Proof.
    intro u.
    split.
    - apply out_at_0_rf.
    - apply out_at_succ_rf.
  Qed.

  Theorem delay_stream_closed_form :
    forall u,
      (fun k => out_at2 u k) = (fun k => match k with O => 0 | S n => u n end).
  Proof.
    intro u.
    apply functional_extensionality.
    intro k.
    destruct k as [|n].
    - apply out_at_0_rf.
    - apply out_at_succ_rf.
  Qed.

  Theorem delay_memory_invariant :
    forall u k, cfg_at2 u (S k) = (SRun, u k).
  Proof.
    apply cfg_at_succ_rf.
  Qed.

  Theorem delay_end_to_end :
    forall u,
      (forall k, out_at2 u k = match k with O => 0 | S n => u n end)
      /\ (forall k, cfg_at2 u (S k) = (SRun, u k)).
  Proof.
    intro u.
    split.
    - rewrite delay_stream_closed_form.
      reflexivity.
    - apply delay_memory_invariant.
  Qed.
End RunFacts.

Section AutomataProductFacts.
  Variable m0 : Mem.

  Definition cfg_at := KO.cfg_at paut SInit m0 pselect.
  Definition out_at := KO.out_at paut SInit m0 pselect.
  Definition run_trace := KO.run_trace paut SInit m0 pselect.

  Lemma cfg_at_succ :
    forall u k, cfg_at u (S k) = (SRun, u k).
  Proof.
    intros u k.
    induction k as [|n IH].
    - reflexivity.
    - unfold cfg_at in IH |- *.
      simpl.
      remember (KO.cfg_at paut SInit m0 pselect u (S n)) as cfg eqn:Hcfg.
      destruct cfg as [s m].
      rewrite IH in Hcfg.
      inversion Hcfg; subst; clear Hcfg.
      reflexivity.
  Qed.

  Lemma out_at_0 :
    forall u, out_at u 0 = 0.
  Proof.
    intros u.
    reflexivity.
  Qed.

  Lemma out_at_succ :
    forall u k, out_at u (S k) = u k.
  Proof.
    intros u k.
    unfold out_at, KO.out_at, KO.out_at_from, KO.step_at, KO.step_at_from, KO.step.
    pose proof (cfg_at_succ u k) as Hcfg.
    unfold cfg_at, KO.cfg_at in Hcfg.
    rewrite Hcfg.
    reflexivity.
  Qed.

  Lemma out_at_ko_0 :
    forall u, KO.out_at paut SInit m0 pselect u 0 = 0.
  Proof.
    intro u.
    reflexivity.
  Qed.

  Lemma out_at_ko_succ :
    forall u k, KO.out_at paut SInit m0 pselect u (S k) = u k.
  Proof.
    intros u k.
    unfold KO.out_at, KO.out_at_from, KO.step_at, KO.step_at_from, KO.step.
    pose proof (cfg_at_succ u k) as Hcfg.
    unfold cfg_at, KO.cfg_at in Hcfg.
    rewrite Hcfg.
    reflexivity.
  Qed.

  Inductive AState : Type :=
  | AOk
  | ABad.

  Definition A_aut : KO.SafetyAutomaton Input :=
    {|
      KO.q := AState;
      KO.q0 := AOk;
      KO.bad := ABad;
      KO.delta := fun _ _ => AOk;
    |}.

  Definition AEdge : Type := { qa : KO.q A_aut & Input }.

  Definition A_aut_e : KO.SafetyAutomatonEdges A_aut :=
    {|
      KO.Edge := AEdge;
      KO.src_e := fun e => projT1 e;
      KO.dst_e := fun _ => AOk;
      KO.label_e := fun _ _ => True;
    |}.

  Definition select_A (qa : KO.q A_aut) (i : Input) : KO.Edge A_aut_e :=
    existT _ qa i.

  Lemma select_A_src :
    forall qa i, KO.src_e A_aut_e (select_A qa i) = qa.
  Proof.
    intros qa i.
    reflexivity.
  Qed.

  Lemma select_A_label :
    forall qa i, KO.label_e A_aut_e (select_A qa i) i.
  Proof.
    intros qa i.
    exact I.
  Qed.

  Inductive GState : Type :=
  | GInit
  | GRun (z : Input)
  | GBad.

  Definition Gdelta (qg : GState) (io : KO.io_val Input Output) : GState :=
    let '(i, o) := io in
    match qg with
    | GInit => if Nat.eqb o 0 then GRun i else GBad
    | GRun z => if Nat.eqb o z then GRun i else GBad
    | GBad => GBad
    end.

  Definition G_aut : KO.SafetyAutomaton (KO.io_val Input Output) :=
    {|
      KO.q := GState;
      KO.q0 := GInit;
      KO.bad := GBad;
      KO.delta := Gdelta;
    |}.

  Definition GEdge : Type := { qg : KO.q G_aut & KO.io_val Input Output }.

  Definition G_aut_e : KO.SafetyAutomatonEdges G_aut :=
    {|
      KO.Edge := GEdge;
      KO.src_e := fun e => projT1 e;
      KO.dst_e := fun e =>
        match e with
        | existT _ qg io => Gdelta qg io
        end;
      KO.label_e := fun e io => io = projT2 e;
    |}.

  Definition select_G (qg : KO.q G_aut) (io : KO.io_val Input Output) : KO.Edge G_aut_e :=
    existT _ qg io.

  Lemma select_G_src :
    forall qg io, KO.src_e G_aut_e (select_G qg io) = qg.
  Proof.
    intros qg io.
    reflexivity.
  Qed.

  Lemma select_G_label :
    forall qg io, KO.label_e G_aut_e (select_G qg io) io.
  Proof.
    intros qg io.
    reflexivity.
  Qed.

  Lemma aut_state_A_all_ok :
    forall u k, KO.aut_state_at_A A_aut_e select_A u k = AOk.
  Proof.
    intros u k.
    induction k as [|n IH]; simpl; reflexivity.
  Qed.

  Lemma aut_state_G_succ :
    forall (u : KO.stream Input) k,
      KO.aut_state_at_G G_aut_e select_G (KO.run_trace_from paut SInit pselect m0 u) (S k) = GRun (u k).
  Proof.
    intros u k.
    remember (KO.run_trace_from paut SInit pselect m0 u) as w eqn:Hw.
    revert u Hw.
    induction k as [|n IH]; intros u Hw.
    - simpl.
      subst w.
      unfold KO.run_trace_from.
      simpl.
      reflexivity.
    - change
        (KO.delta_G G_aut_e select_G
           (KO.aut_state_at_G G_aut_e select_G w (S n))
           (w (S n)) = GRun (u (S n))).
      specialize (IH u Hw).
      rewrite IH.
      subst w.
      unfold KO.run_trace_from.
      simpl.
      change (KO.out_at_from paut SInit pselect m0 u (S n))
        with (KO.out_at paut SInit m0 pselect u (S n)).
      rewrite (out_at_ko_succ u n).
      rewrite Nat.eqb_refl.
      reflexivity.
  Qed.

  Theorem avoids_bad_A_delay :
    forall u, KO.avoids_bad_A A_aut_e select_A u.
  Proof.
    intros u k.
    rewrite aut_state_A_all_ok.
    discriminate.
  Qed.

  Theorem avoids_bad_G_delay :
    forall (u : KO.stream Input), KO.avoids_bad_G G_aut_e select_G (KO.run_trace paut SInit m0 pselect u).
  Proof.
    intros u k.
    destruct k as [|n].
    - simpl.
      discriminate.
    - change
        (KO.aut_state_at_G G_aut_e select_G (KO.run_trace paut SInit m0 pselect u) (S n))
        with
        (KO.aut_state_at_G G_aut_e select_G (KO.run_trace_from paut SInit pselect m0 u) (S n)).
      rewrite aut_state_G_succ.
      discriminate.
  Qed.

  Definition run_ps := KO.run_product_state paut SInit m0 pselect A_aut_e G_aut_e select_A select_G.

  Theorem product_state_0 :
    forall u,
      run_ps u 0 =
      {| KO.ps_prog := SInit; KO.ps_a := (AOk : KO.q A_aut); KO.ps_g := (GInit : KO.q G_aut) |}.
  Proof.
    intros u.
    reflexivity.
  Qed.

  Theorem product_state_succ :
    forall u k,
      run_ps u (S k) =
      {| KO.ps_prog := SRun; KO.ps_a := (AOk : KO.q A_aut); KO.ps_g := (GRun (u k) : KO.q G_aut) |}.
  Proof.
    intros u k.
    unfold run_ps, KO.run_product_state, KO.run_product_state_from.
    pose proof (cfg_at_succ u k) as Hcfg.
    unfold cfg_at, KO.cfg_at in Hcfg.
    remember (KO.cfg_at_from paut SInit pselect m0 u (S k)) as cfg eqn:Hcfg'.
    destruct cfg as [s m].
    rewrite Hcfg in Hcfg'.
    inversion Hcfg'; subst; clear Hcfg'.
    inversion Hcfg; subst; clear Hcfg.
    rewrite (aut_state_A_all_ok u (S k)).
    rewrite (aut_state_G_succ u k).
    reflexivity.
  Qed.
End AutomataProductFacts.

End DelayIntProof.
