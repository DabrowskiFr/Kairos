From Stdlib Require Import List ZArith Lia Classical_Prop.
From obc2why3 Require Import proof.
Import ListNotations.
Open Scope Z_scope.

(* Minimal imperative language used to model the generated Why3. *)
Section SyncLang.

Definition var := nat.
Definition val := Z.
(* Program state as a total map from variables to values. *)
Definition state := var -> val.
Definition run_trace := nat -> state.

Definition update (s : state) (x : var) (v : val) : state :=
  fun y => if Nat.eqb x y then v else s y.

Inductive binop := Add | Sub | Mul.

(* Expressions with old access to the trace. *)
Inductive expr :=
| EConst : val -> expr
| EVar : var -> expr
| EOld : var -> expr
| EBin : binop -> expr -> expr -> expr.

(* Expression evaluation with access to previous state and the trace. *)
Fixpoint eval_expr (t : run_trace) (i : nat) (prev s : state) (e : expr) : val :=
  match e with
  | EConst v => v
  | EVar x => s x
  | EOld x => prev x
  | EBin op a b =>
      let va := eval_expr t i prev s a in
      let vb := eval_expr t i prev s b in
      match op with
      | Add => va + vb
      | Sub => va - vb
      | Mul => va * vb
      end
  end.

(* Boolean expressions. *)
Inductive bexpr :=
| BTrue
| BFalse
| BEq : expr -> expr -> bexpr
| BLe : expr -> expr -> bexpr
| BAnd : bexpr -> bexpr -> bexpr
| BNot : bexpr -> bexpr.

(* Boolean evaluation with access to previous state and the trace. *)
Fixpoint eval_bexpr (t : run_trace) (i : nat) (prev s : state) (b : bexpr) : bool :=
  match b with
  | BTrue => true
  | BFalse => false
  | BEq a b => Z.eqb (eval_expr t i prev s a) (eval_expr t i prev s b)
  | BLe a b => Z.leb (eval_expr t i prev s a) (eval_expr t i prev s b)
  | BAnd a b => andb (eval_bexpr t i prev s a) (eval_bexpr t i prev s b)
  | BNot a => negb (eval_bexpr t i prev s a)
  end.

(* Assertions are part of the specification layer; they may refer to the
   trace, time, previous state, and current state. *)
Definition assertion := run_trace -> nat -> state -> state -> Prop.

(* Commands in the target Why3-like core language. *)
Inductive cmd :=
| CSkip
| CAssign : var -> expr -> cmd
| CSeq : cmd -> cmd -> cmd
| CIf : bexpr -> cmd -> cmd -> cmd
| CAssume : bexpr -> cmd
| CCall : nat -> list expr -> list var -> cmd.

(* Instance specifications for calls:
   inst_pre is the call precondition over the arguments and current state,
   inst_post relates pre-state and post-state for a call. *)
Variable inst_pre : nat -> list val -> assertion.
Variable inst_post : nat -> list val -> run_trace -> nat -> state -> state -> Prop.

(* Evaluation of argument lists for calls. *)
Fixpoint eval_args (t : run_trace) (i : nat) (prev s : state) (es : list expr) : list val :=
  match es with
  | [] => []
  | e :: tl => eval_expr t i prev s e :: eval_args t i prev s tl
  end.

(* Big-step imperative semantics. *)
Inductive exec : cmd -> run_trace -> nat -> state -> state -> state -> Prop :=
| ExecSkip : forall t i prev s, exec CSkip t i prev s s
| ExecAssign : forall t i prev s x e,
    exec (CAssign x e) t i prev s (update s x (eval_expr t i prev s e))
| ExecSeq : forall t i prev s s1 s' c1 c2,
    exec c1 t i prev s s1 ->
    exec c2 t i prev s1 s' ->
    exec (CSeq c1 c2) t i prev s s'
| ExecIfTrue : forall t i prev s s' b c1 c2,
    eval_bexpr t i prev s b = true ->
    exec c1 t i prev s s' ->
    exec (CIf b c1 c2) t i prev s s'
| ExecIfFalse : forall t i prev s s' b c1 c2,
    eval_bexpr t i prev s b = false ->
    exec c2 t i prev s s' ->
    exec (CIf b c1 c2) t i prev s s'
| ExecAssume : forall t i prev s b,
    eval_bexpr t i prev s b = true ->
    exec (CAssume b) t i prev s s
| ExecCall : forall t i prev s s' name args rets,
    inst_pre name (eval_args t i prev s args) t i prev s ->
    inst_post name (eval_args t i prev s args) t i s s' ->
    exec (CCall name args rets) t i prev s s'.

(* Partial correctness judgment. *)
Definition hoare (P : assertion) (c : cmd) (Q : assertion) : Prop :=
  forall t i prev s s',
    exec c t i prev s s' ->
    P t i prev s ->
    Q t i prev s'.

(* Weakest precondition for the core commands. *)
Fixpoint wp (c : cmd) (Q : assertion) {struct c} : assertion :=
  match c with
  | CSkip => Q
  | CAssign x e => fun t i prev s => Q t i prev (update s x (eval_expr t i prev s e))
  | CSeq c1 c2 => wp c1 (wp c2 Q)
  | CIf b c1 c2 =>
      fun t i prev s =>
        (eval_bexpr t i prev s b = true -> wp c1 Q t i prev s) /\
        (eval_bexpr t i prev s b = false -> wp c2 Q t i prev s)
  | CAssume b => fun t i prev s => eval_bexpr t i prev s b = true -> Q t i prev s
  | CCall name args rets =>
      fun t i prev s =>
        inst_pre name (eval_args t i prev s args) t i prev s ->
        forall s', inst_post name (eval_args t i prev s args) t i s s' -> Q t i prev s'
  end.

(* VC validity predicate. *)
Definition vc (P : assertion) (c : cmd) (Q : assertion) : Prop :=
  forall t i prev s, P t i prev s -> wp c Q t i prev s.

(* Soundness of wp wrt. the big-step semantics. *)
Lemma wp_sound :
  forall c Q, hoare (wp c Q) c Q.
Proof.
  induction c as
      [ (* CSkip *)
      | (* CAssign *) x e
      | (* CSeq *) c1 IHc1 c2 IHc2
      | (* CIf *) b c1 IHc1 c2 IHc2
      | (* CAssume *) b
      | (* CCall *) name args rets
      ]; intros Q t i prev s s' Hexec Hwp; simpl in *.
  - inversion Hexec; subst. exact Hwp.
  - inversion Hexec; subst. exact Hwp.
  - inversion Hexec; subst.
    eapply IHc2; eauto.
    eapply IHc1; eauto.
  - inversion Hexec; subst;
      try (destruct Hwp as [Ht _]; eapply IHc1; eauto; apply Ht; eauto);
      try (destruct Hwp as [_ Hf]; eapply IHc2; eauto; apply Hf; eauto).
  - inversion Hexec; subst. apply Hwp. eauto.
  - inversion Hexec; subst. eapply Hwp; eauto.
Qed.

(* VCGen soundness: valid VCs imply Hoare correctness. *)
Theorem vc_sound :
  forall P c Q, vc P c Q -> hoare P c Q.
Proof.
  intros P c Q Hvc t i prev s s' Hexec Hp.
  apply (wp_sound c Q t i prev s s'); auto.
Qed.

End SyncLang.

(* OBC-level packaging for nodes with monitor-style contracts. *)
Section OBC.

(* Node structure as used by the monitor pipeline. *)
Record node := {
  inputs : list var;
  outputs : list var;
  locals : list var;
  step_body : cmd;
  assumes_list : list assertion;
  guarantees_list : list assertion;
}.

(* Conjunction of a list of assertions. *)
Definition conj (ps : list assertion) : assertion :=
  fun t i prev s => Forall (fun P => P t i prev s) ps.

Definition step_pre (n : node) : assertion :=
  fun t i prev s => conj (assumes_list n) t i prev s.

Definition step_post (n : node) : assertion :=
  fun t i prev s => conj (guarantees_list n) t i prev s.

Variable inst_pre : nat -> list val -> assertion.
Variable inst_post : nat -> list val -> run_trace -> nat -> state -> state -> Prop.

(* VC obligation for a node. *)
Definition node_vc (n : node) : Prop :=
  vc inst_pre inst_post (step_pre n) (step_body n) (step_post n).

Definition exec_node (n : node) (t : run_trace) : Prop :=
  forall i, exec inst_pre inst_post (step_body n) t i (t i) (t i) (t (S i)).

(* One-step correctness of a node from its VC. *)
Lemma node_step_correct :
  forall n t i,
    node_vc n ->
    exec inst_pre inst_post (step_body n) t i (t i) (t i) (t (S i)) ->
    step_pre n t i (t i) (t i) ->
    step_post n t i (t i) (t (S i)).
Proof.
  intros n t i Hvc Hexec Hpre.
  unfold node_vc in Hvc.
  pose proof (vc_sound inst_pre inst_post (step_pre n) (step_body n) (step_post n) Hvc)
    as Hhoare.
  apply (Hhoare _ _ _ _ _ Hexec Hpre).
Qed.

End OBC.

(* Linking the program invariant with LTL satisfaction. *)
Section MonitorLink.

Definition trace_state : Type := @trace state.

Definition AP := state -> bool.
Definition eval_atom (s : state) (P : AP) : bool := P s.

(* Monitor residual along a trace. *)
Definition mon_trace (t : trace_state) (q0 : @ltl AP) (i : nat) : @ltl AP :=
  @run state AP eval_atom t q0 i.

(* Invariant over residuals implies the initial LTL formula. *)
Lemma monitor_invariant_implies_spec :
  forall (t : trace_state) (q0 : @ltl AP),
    (forall i, @eval_ltl state AP eval_atom t i (mon_trace t q0 i)) ->
    @eval_ltl state AP eval_atom t 0%nat q0.
Proof.
  intros t q0 Hinv.
  specialize (Hinv 0%nat).
  apply (proj1 (@run_equiv state AP eval_atom t q0 0%nat)).
  exact Hinv.
Qed.

Section NodeToLTL.

Variable inst_pre : nat -> list val -> assertion.
Variable inst_post : nat -> list val -> run_trace -> nat -> state -> state -> Prop.

Variable n : node.
Variable q0 : @ltl AP.
Variable mon_inv : assertion.

Hypothesis mon_inv_at_init :
  forall t, mon_inv t 0%nat (t 0%nat) (t 0%nat).

Hypothesis mon_inv_from_post :
  forall t i,
    step_post n t i (t i) (t (S i)) ->
    mon_inv t (S i) (t (S i)) (t (S i)).

Hypothesis mon_inv_implies_ltl :
  forall t i,
    mon_inv t i (t i) (t i) ->
    @eval_ltl state AP eval_atom t i (mon_trace t q0 i).

(* End-to-end: VCGen correctness + monitor invariant imply LTL spec. *)
Theorem vcgen_and_instrumentation_correct :
  forall t,
    node_vc inst_pre inst_post n ->
    exec_node inst_pre inst_post n t ->
    (forall i, step_pre n t i (t i) (t i)) ->
    @eval_ltl state AP eval_atom t 0%nat q0.
Proof.
  intros t Hvc Hexec Hpre.
  assert (Hinv : forall i, mon_inv t i (t i) (t i)).
  { intro i.
    induction i as [|i IH].
    - apply mon_inv_at_init.
    - specialize (Hexec i).
      specialize (Hpre i).
      pose proof (node_step_correct inst_pre inst_post n t i Hvc Hexec Hpre) as Hpost.
      apply mon_inv_from_post in Hpost.
      exact Hpost.
  }
  apply monitor_invariant_implies_spec.
  intro i. apply mon_inv_implies_ltl. apply Hinv.
Qed.

End NodeToLTL.

End MonitorLink.
