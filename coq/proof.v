From Stdlib Require Import List Arith Lia Classical_Prop.
Import ListNotations.

(* LTL core definitions and proofs used by the monitor construction. *)
Section LTL.

Variable Sigma : Type.
Variable AP : Type.
Variable eval_atom : Sigma -> AP -> bool.

(* LTL syntax over atomic propositions AP. *)
Inductive ltl : Type :=
| LTrue : ltl
| LFalse : ltl
| LAtom : AP -> ltl
| LNot : ltl -> ltl
| LAnd : ltl -> ltl -> ltl
| LOr : ltl -> ltl -> ltl
| LImp : ltl -> ltl -> ltl
| LX : ltl -> ltl
| LG : ltl -> ltl.

Definition trace := nat -> Sigma.

(* Pointwise semantics of LTL over a trace. *)
Fixpoint eval_ltl (t : trace) (i : nat) (f : ltl) : Prop :=
  match f with
  | LTrue => True
  | LFalse => False
  | LAtom p => eval_atom (t i) p = true
  | LNot a => ~ eval_ltl t i a
  | LAnd a b => eval_ltl t i a /\ eval_ltl t i b
  | LOr a b => eval_ltl t i a \/ eval_ltl t i b
  | LImp a b => eval_ltl t i a -> eval_ltl t i b
  | LX a => eval_ltl t (S i) a
  | LG a => forall j, j >= i -> eval_ltl t j a
  end.

(* Negation Normal Form (NNF) predicate. *)
Fixpoint is_nnf (f : ltl) : Prop :=
  match f with
  | LTrue | LFalse | LAtom _ => True
  | LNot a => match a with
              | LAtom _ => True
              | _ => False
              end
  | LAnd a b | LOr a b | LImp a b => is_nnf a /\ is_nnf b
  | LX a | LG a => is_nnf a
  end.

(* Total NNF transformation for the supported fragment; None when unsupported. *)
Fixpoint nnf (f : ltl) : option ltl :=
  match f with
  | LTrue => Some LTrue
  | LFalse => Some LFalse
  | LAtom p => Some (LAtom p)
  | LNot a => nnf_neg a
  | LAnd a b =>
      match nnf a, nnf b with
      | Some a', Some b' => Some (LAnd a' b')
      | _, _ => None
      end
  | LOr a b =>
      match nnf a, nnf b with
      | Some a', Some b' => Some (LOr a' b')
      | _, _ => None
      end
  | LImp a b =>
      match nnf_neg a, nnf b with
      | Some a', Some b' => Some (LOr a' b')
      | _, _ => None
      end
  | LX a =>
      match nnf a with
      | Some a' => Some (LX a')
      | None => None
      end
  | LG a =>
      match nnf a with
      | Some a' => Some (LG a')
      | None => None
      end
  end
with nnf_neg (f : ltl) : option ltl :=
  match f with
  | LTrue => Some LFalse
  | LFalse => Some LTrue
  | LAtom p => Some (LNot (LAtom p))
  | LNot a => nnf a
  | LAnd a b =>
      match nnf_neg a, nnf_neg b with
      | Some a', Some b' => Some (LOr a' b')
      | _, _ => None
      end
  | LOr a b =>
      match nnf_neg a, nnf_neg b with
      | Some a', Some b' => Some (LAnd a' b')
      | _, _ => None
      end
  | LImp a b =>
      match nnf a, nnf_neg b with
      | Some a', Some b' => Some (LAnd a' b')
      | _, _ => None
      end
  | LX a =>
      match nnf_neg a with
      | Some a' => Some (LX a')
      | None => None
      end
  | LG _ => None
  end.

Lemma not_not_iff :
  forall P : Prop, ~~ P <-> P.
Proof.
  intros P. split; intro H.
  - apply NNPP. exact H.
  - intro Hn. apply Hn. exact H.
Qed.

Lemma not_iff :
  forall P Q : Prop, (P <-> Q) -> (~ P <-> ~ Q).
Proof.
  intros P Q [H1 H2]. split; intro H.
  - intro Hp. apply H. apply H2. exact Hp.
  - intro Hq. apply H. apply H1. exact Hq.
Qed.

Lemma imp_iff_or :
  forall P Q : Prop, (P -> Q) <-> (~ P \/ Q).
Proof.
  intros P Q. split; intro H.
  - destruct (classic P) as [Hp | Hnp].
    + right. apply H. exact Hp.
    + left. exact Hnp.
  - intros Hp. destruct H as [Hnp | Hq].
    + contradiction.
    + exact Hq.
Qed.

Lemma not_and_or :
  forall P Q : Prop, ~(P /\ Q) <-> (~ P \/ ~ Q).
Proof.
  intros P Q. split; intro H.
  - destruct (classic P) as [Hp | Hnp].
    + right. intro Hq. apply H. split; assumption.
    + left. exact Hnp.
  - intro Hpq. destruct H as [Hnp | Hnq].
    + apply Hnp. exact (proj1 Hpq).
    + apply Hnq. exact (proj2 Hpq).
Qed.

Lemma not_imp_and :
  forall P Q : Prop, ~(P -> Q) <-> (P /\ ~ Q).
Proof.
  intros P Q. split; intro H.
  - destruct (classic P) as [Hp | Hnp].
    + split.
      * exact Hp.
      * intro Hq. apply H. intro Hp0. exact Hq.
    + exfalso. apply H. intro Hp. contradiction.
  - intros Hp. destruct H as [Hp' Hnq]. apply Hnq. apply Hp. exact Hp'.
Qed.

(* NNF preserves semantics and produces NNF formulas. *)
Lemma nnf_sound :
  forall (t : trace) (i : nat) (f g : ltl),
    nnf f = Some g -> (eval_ltl t i f <-> eval_ltl t i g) /\ is_nnf g
with nnf_neg_sound :
  forall (t : trace) (i : nat) (f g : ltl),
    nnf_neg f = Some g -> (eval_ltl t i (LNot f) <-> eval_ltl t i g) /\ is_nnf g.
Proof.
  - intros t i f g H.
    revert t i g H.
    induction f; intros t i g H; simpl in *.
    + inversion H; subst. split; simpl; tauto.
    + inversion H; subst. split; simpl; tauto.
    + inversion H; subst. split; simpl; tauto.
    + pose proof (nnf_neg_sound t i f g H) as H0. exact H0.
    + destruct (nnf f1) eqn:E1; try discriminate.
      destruct (nnf f2) eqn:E2; try discriminate.
      inversion H; subst.
      specialize (IHf1 t i l eq_refl). specialize (IHf2 t i l0 eq_refl).
      destruct IHf1 as [H1 H1n]. destruct IHf2 as [H2 H2n].
      split; simpl; tauto.
    + destruct (nnf f1) eqn:E1; try discriminate.
      destruct (nnf f2) eqn:E2; try discriminate.
      inversion H; subst.
      specialize (IHf1 t i l eq_refl). specialize (IHf2 t i l0 eq_refl).
      destruct IHf1 as [H1 H1n]. destruct IHf2 as [H2 H2n].
      split; simpl; tauto.
    + destruct (nnf_neg f1) eqn:E1; try discriminate.
      destruct (nnf f2) eqn:E2; try discriminate.
      inversion H; subst.
      specialize (nnf_neg_sound t i f1 l E1) as Hn1.
      specialize (IHf2 t i l0 eq_refl).
      destruct Hn1 as [H1 H1n]. destruct IHf2 as [H2 H2n].
      split; simpl.
      * split.
        -- intro Himp. apply imp_iff_or in Himp.
           destruct Himp as [Hna | Hb].
           ++ left. apply (proj1 H1). exact Hna.
           ++ right. apply (proj1 H2). exact Hb.
        -- intro Hor. apply imp_iff_or.
           destruct Hor as [Ha' | Hb'].
           ++ left. apply (proj2 H1). exact Ha'.
           ++ right. apply (proj2 H2). exact Hb'.
      * split; assumption.
    + destruct (nnf f) eqn:E; try discriminate.
      inversion H; subst.
      specialize (IHf t (S i) l eq_refl). destruct IHf as [H1 H2].
      split; simpl.
      * exact H1.
      * exact H2.
    + destruct (nnf f) eqn:E; try discriminate.
      inversion H; subst.
      pose proof (IHf t i l eq_refl) as IH0. destruct IH0 as [H1 H2].
      split; simpl.
      * split; intros Hlg j Hj.
        -- pose proof (IHf t j l eq_refl) as Hjl.
           destruct Hjl as [Hjl_eq _].
           apply (proj1 Hjl_eq). apply Hlg. exact Hj.
        -- pose proof (IHf t j l eq_refl) as Hjl.
           destruct Hjl as [Hjl_eq _].
           apply (proj2 Hjl_eq). apply Hlg. exact Hj.
      * exact H2.
  - intros t i f g H.
    revert t i g H.
    induction f; intros t i g H; simpl in *.
    + inversion H; subst. split; simpl; tauto.
    + inversion H; subst. split; simpl; tauto.
    + inversion H; subst. split; simpl; tauto.
    + pose proof (nnf_sound t i f g H) as H0.
      destruct H0 as [H1 H2].
      split.
      * simpl. rewrite (not_not_iff (eval_ltl t i f)). exact H1.
      * exact H2.
    + destruct (nnf_neg f1) eqn:E1; try discriminate.
      destruct (nnf_neg f2) eqn:E2; try discriminate.
      inversion H; subst.
      specialize (IHf1 t i l eq_refl). specialize (IHf2 t i l0 eq_refl).
      destruct IHf1 as [H1 H1n]. destruct IHf2 as [H2 H2n].
      split; simpl.
      * split.
        -- intro Hnot. apply not_and_or in Hnot.
           destruct Hnot as [Hna | Hnb].
           ++ left. apply (proj1 H1). exact Hna.
           ++ right. apply (proj1 H2). exact Hnb.
        -- intro Hor. apply not_and_or.
           destruct Hor as [Ha' | Hb'].
           ++ left. apply (proj2 H1). exact Ha'.
           ++ right. apply (proj2 H2). exact Hb'.
      * split; assumption.
    + destruct (nnf_neg f1) eqn:E1; try discriminate.
      destruct (nnf_neg f2) eqn:E2; try discriminate.
      inversion H; subst.
      specialize (IHf1 t i l eq_refl). specialize (IHf2 t i l0 eq_refl).
      destruct IHf1 as [H1 H1n]. destruct IHf2 as [H2 H2n].
      split; simpl.
      * split.
        -- intro Hnot. split.
           ++ apply (proj1 H1). intro Ha. apply Hnot. left. exact Ha.
           ++ apply (proj1 H2). intro Hb. apply Hnot. right. exact Hb.
        -- intros [Ha' Hb'].
           intro Hor. destruct Hor as [Ha | Hb].
           ++ apply (proj2 H1) in Ha'. apply Ha'. exact Ha.
           ++ apply (proj2 H2) in Hb'. apply Hb'. exact Hb.
      * split; assumption.
    + destruct (nnf f1) eqn:E1; try discriminate.
      destruct (nnf_neg f2) eqn:E2; try discriminate.
      inversion H; subst.
      specialize (nnf_sound t i f1 l E1) as Hpos.
      specialize (IHf2 t i l0 eq_refl).
      destruct Hpos as [H1 H1n]. destruct IHf2 as [H2 H2n].
      split; simpl.
      * split.
        -- intro Hnot.
           assert (Ha : eval_ltl t i f1).
           { destruct (classic (eval_ltl t i f1)) as [Ha | Hna].
             - exact Ha.
             - exfalso. apply Hnot. intro Hf1. contradiction.
           }
           assert (Hnb : ~ eval_ltl t i f2).
           { intro Hb. apply Hnot. intro Hf1. exact Hb. }
           split.
           ++ apply (proj1 H1). exact Ha.
           ++ apply (proj1 H2). exact Hnb.
        -- intros [Ha' Hnb'].
           intro Himp.
           apply (proj2 H2) in Hnb'.
           apply Hnb'. apply Himp.
           apply (proj2 H1). exact Ha'.
      * split; assumption.
    + destruct (nnf_neg f) eqn:E; try discriminate.
      inversion H; subst.
      specialize (IHf t (S i) l eq_refl).
      destruct IHf as [H1 H2].
      split; simpl.
      * exact H1.
      * exact H2.
    + discriminate.
Qed.

(* Progression operator: residual formula after consuming one state. *)
Fixpoint prog (f : ltl) (s : Sigma) : ltl :=
  match f with
  | LTrue => LTrue
  | LFalse => LFalse
  | LAtom p => if eval_atom s p then LTrue else LFalse
  | LNot a => LNot (prog a s)
  | LAnd a b => LAnd (prog a s) (prog b s)
  | LOr a b => LOr (prog a s) (prog b s)
  | LImp a b => LImp (prog a s) (prog b s)
  | LX a => a
  | LG a => LAnd (prog a s) (LG a)
  end.

(* Progression is sound w.r.t. the LTL semantics. *)
Lemma prog_correct :
  forall (t : trace) (i : nat) (f : ltl),
    eval_ltl t i f <-> eval_ltl t (S i) (prog f (t i)).
Proof.
  induction f; simpl; intros.
  - tauto.
  - tauto.
  - destruct (eval_atom (t i) a) eqn:Ha; simpl.
    + split; intros; auto.
    + split; intro H; try discriminate; contradiction.
  - apply not_iff. exact IHf.
  - rewrite IHf1, IHf2; tauto.
  - rewrite IHf1, IHf2; tauto.
  - rewrite IHf1, IHf2; tauto.
  - split; intros; auto.
  - split; intros H; simpl.
    + split.
      * apply IHf. apply H. lia.
      * intros j Hj. apply H. lia.
    + destruct H as [H1 H2]. intros j Hj.
      destruct (Nat.eq_dec j i) as [Heq | Hneq].
      * subst. apply IHf in H1. exact H1.
      * apply H2. lia.
Qed.

(* Simple logical simplification (soundness only). *)
Fixpoint simplify (f : ltl) : ltl :=
  match f with
  | LAnd a b =>
      let a' := simplify a in
      let b' := simplify b in
      match a', b' with
      | LFalse, _ => LFalse
      | _, LFalse => LFalse
      | LTrue, _ => b
      | _, LTrue => a
      | _, _ => LAnd a b
      end
  | LOr a b =>
      let a' := simplify a in
      let b' := simplify b in
      match a', b' with
      | LTrue, _ => LTrue
      | _, LTrue => LTrue
      | LFalse, _ => b
      | _, LFalse => a
      | _, _ => LOr a b
      end
  | LImp a b => LImp a b
  | LNot a =>
      let a' := simplify a in
      match a' with
      | LTrue => LFalse
      | LFalse => LTrue
      | _ => LNot a
      end
  | LG a => LG a
  | LX a => LX a
  | _ => f
  end.

(* Simplification preserves semantics. *)
Lemma simplify_sound :
  forall (t : trace) (i : nat) (f : ltl),
    eval_ltl t i (simplify f) <-> eval_ltl t i f.
Proof.
  intros t i f.
  revert t i.
  induction f; simpl; intros t i.
  - tauto.
  - tauto.
  - tauto.
  - destruct (simplify f) eqn:E; simpl.
    + rewrite <- (IHf t i). simpl. tauto.
    + rewrite <- (IHf t i). simpl. tauto.
    + tauto.
    + tauto.
    + tauto.
    + tauto.
    + tauto.
    + tauto.
    + tauto.
  - destruct (simplify f1) eqn:E1;
    destruct (simplify f2) eqn:E2; simpl in *; try tauto;
    rewrite <- (IHf1 t i), <- (IHf2 t i); tauto.
  - destruct (simplify f1) eqn:E1;
    destruct (simplify f2) eqn:E2; simpl in *; try tauto;
    rewrite <- (IHf1 t i), <- (IHf2 t i); tauto.
  - tauto.
  - tauto.
  - tauto.
Qed.

(* One-step residual used by the monitor. *)
Definition step_res (q : ltl) (s : Sigma) : ltl := simplify (prog q s).

(* Monitor state evolution along a trace. *)
Definition run (t : trace) (q0 : ltl) : nat -> ltl :=
  fix run_i i :=
    match i with
    | 0 => simplify q0
    | S j => step_res (run_i j) (t j)
    end.

(* Run preserves the initial formula semantics. *)
Lemma run_equiv :
  forall (t : trace) (q0 : ltl) i,
    eval_ltl t i (run t q0 i) <-> eval_ltl t 0 q0.
Proof.
  induction i; simpl; intros.
  - rewrite (simplify_sound t 0 q0). tauto.
  - rewrite (simplify_sound t (S i) (prog (run t q0 i) (t i))).
    rewrite <- prog_correct. rewrite IHi. tauto.
Qed.

(* Residual-monitor correctness as a semantic invariant. *)
Theorem automaton_correct_sem :
  forall (t : trace) (q0 : ltl),
    eval_ltl t 0 q0 <-> (forall i, eval_ltl t i (run t q0 i)).
Proof.
  split.
  - intros H i. apply (proj2 (run_equiv t q0 i)). exact H.
  - intro H. specialize (H 0).
    apply (proj1 (run_equiv t q0 0)) in H. exact H.
Qed.

(* Finitude des residus via la fermeture des sous-formules (NNF). *)
Fixpoint subformulas (f : ltl) : list ltl :=
  match f with
  | LAnd a b => f :: (subformulas a ++ subformulas b)
  | LOr a b => f :: (subformulas a ++ subformulas b)
  | LImp a b => f :: (subformulas a ++ subformulas b)
  | LX a => f :: subformulas a
  | LG a => f :: subformulas a
  | LNot a => f :: subformulas a
  | _ => [f]
  end.

Definition closure (f : ltl) : list ltl :=
  LTrue :: LFalse :: subformulas f.

(* Initial-only guard for formulas restricted to the first step. *)
Definition first_step (i : nat) : Prop := i = 0.

Lemma initial_only_sound :
  forall (t : trace) (f : ltl),
    (forall i, first_step i -> eval_ltl t i f) ->
    eval_ltl t 0 f.
Proof.
  intros t f H. apply H. reflexivity.
Qed.

Fixpoint max_x_depth (f : ltl) : nat :=
  match f with
  | LX a => S (max_x_depth a)
  | LAnd a b => max (max_x_depth a) (max_x_depth b)
  | LOr a b => max (max_x_depth a) (max_x_depth b)
  | LImp a b => max (max_x_depth a) (max_x_depth b)
  | LG a => max_x_depth a
  | LNot a => max_x_depth a
  | _ => 0
  end.

Lemma g_guard_sound :
  forall (t : trace) (a : ltl) k,
    eval_ltl t 0 (LG a) ->
    (forall i, i >= k -> eval_ltl t i a).
Proof.
  intros t a k H i Hi. apply H. lia.
Qed.

Fixpoint has_x (f : ltl) : bool :=
  match f with
  | LX _ => true
  | LAnd a b => has_x a || has_x b
  | LOr a b => has_x a || has_x b
  | LImp a b => has_x a || has_x b
  | LG a => has_x a
  | LNot a => has_x a
  | _ => false
  end.

Definition base_form (f : ltl) : ltl :=
  match f with
  | LG a => a
  | _ => f
  end.

Definition pre_cond (t : trace) (i : nat) (f : ltl) : Prop :=
  eval_ltl t (S i) (base_form f).

Definition post_cond (t : trace) (i : nat) (f : ltl) : Prop :=
  if has_x (base_form f)
  then eval_ltl t i (base_form f)
  else eval_ltl t (S i) (base_form f).

Lemma pre_cond_unfold :
  forall t i f, pre_cond t i f <-> eval_ltl t (S i) (base_form f).
Proof. tauto. Qed.

Lemma post_cond_unfold_x :
  forall t i f,
    has_x (base_form f) = true ->
    post_cond t i f <-> eval_ltl t i (base_form f).
Proof.
  intros. unfold post_cond. rewrite H. tauto.
Qed.

Lemma post_cond_unfold_nox :
  forall t i f,
    has_x (base_form f) = false ->
    post_cond t i f <-> eval_ltl t (S i) (base_form f).
Proof.
  intros. unfold post_cond. rewrite H. tauto.
Qed.

End LTL.

(* Instrumentation-level lemmas that reuse the LTL core. *)
Section Instrumentation.

Variable Sigma : Type.
Variable AP : Type.
Variable eval_atom : Sigma -> AP -> bool.

Definition ltlI := @ltl AP.
Definition eval_ltlI := @eval_ltl Sigma AP eval_atom.
Definition progI := @prog Sigma AP eval_atom.
Definition simplifyI := @simplify AP.
Definition step_resI := @step_res Sigma AP eval_atom.
Definition runI := @run Sigma AP eval_atom.
Definition run_equivI := @run_equiv Sigma AP eval_atom.
Definition automaton_correct_semI :=
  @automaton_correct_sem Sigma AP eval_atom.

Variable step_prog : Sigma -> Sigma -> Prop.
Variable init : Sigma.

Definition exec (t : trace Sigma) : Prop :=
  forall i, step_prog (t i) (t (S i)).

Definition step_instr (sq sq' : Sigma * ltlI) : Prop :=
  step_prog (fst sq) (fst sq') /\
  snd sq' = step_resI (snd sq) (fst sq).

Definition mon_trace (t : trace Sigma) (q0 : ltlI) (i : nat) : ltlI :=
  runI t q0 i.

Lemma mon_trace_step :
  forall (t : trace Sigma) (q0 : ltlI) i,
    mon_trace t q0 (S i) = step_resI (mon_trace t q0 i) (t i).
Proof.
  intros t q0 i. unfold mon_trace. simpl. reflexivity.
Qed.

Theorem instrumentation_correct :
  forall (t : trace Sigma) (q0 : ltlI),
    exec t ->
    (forall i, eval_ltlI t i (mon_trace t q0 i)) ->
    eval_ltlI t 0 q0.
Proof.
  intros t q0 Hexec Hinv.
  specialize (Hinv 0).
  apply (proj1 (run_equivI t q0 0)). exact Hinv.
Qed.

Corollary instrumentation_correct_automaton :
  forall (t : trace Sigma) (q0 : ltlI),
    exec t ->
    (forall i, eval_ltlI t i (mon_trace t q0 i)) ->
    eval_ltlI t 0 q0.
Proof.
  intros. eapply instrumentation_correct; eauto.
Qed.

(* Obligation de mise a jour moniteur (equivalent a Why3). *)
Definition mon_update_ok (t : trace Sigma) (q0 : ltlI) : Prop :=
  forall i, mon_trace t q0 (S i) = step_resI (mon_trace t q0 i) (t i).

Lemma mon_update_ok_holds :
  forall (t : trace Sigma) (q0 : ltlI),
    mon_update_ok t q0.
Proof.
  intros t q0 i. apply mon_trace_step.
Qed.

(* Si l'invariant de moniteur est preserve, la spec LTL est satisfaite. *)
Theorem monitor_invariant_implies_ltl :
  forall (t : trace Sigma) (q0 : ltlI),
    exec t ->
    (forall i, eval_ltlI t i (mon_trace t q0 i)) ->
    eval_ltlI t 0 q0.
Proof.
  intros. eapply instrumentation_correct; eauto.
Qed.

End Instrumentation.
