From Stdlib Require Import ZArith Lia.
From SpecV2 Require Import
  ReactiveModel
  ConditionalSafety
  ExplicitProduct
  GeneratedClauses
  RelationalTriples
  Soundness.

Open Scope Z_scope.
Set Implicit Arguments.

(** * Resettable Delay Example

    This file is the concrete instantiation of the abstract theory on the
    running example used in the paper. The proof style is intentionally not
    ad hoc: we build the concrete program and specification, define the user
    invariant required by the reduction, prove the generated triples valid, and
    conclude with the abstract soundness theorem. *)

(** Control states of the normalized node. [RDInit] is the mode before the
    first data tick has been integrated, whereas [RDRun] is the steady mode. *)
Inductive RDState : Type :=
| RDInit
| RDRun.

(** Concrete transition labels selected by the total tick function. *)
Inductive RDTrans : Type :=
| TInitReset
| TInitData
| TRunReset
| TRunData.

(** Inputs are pairs [(reset, x)]. *)
Definition RDInput : Type := bool * Z.

(** Accessors for the concrete input alphabet. *)
Definition rd_reset (i : RDInput) : bool := fst i.
Definition rd_x (i : RDInput) : Z := snd i.

(** Concrete reactive program for resettable delay. The memory stores the last
    relevant data value. Reset transitions emit and store [0]; ordinary run
    transitions emit the current memory and store the new input value. *)
Definition resettable_delay_program : ReactiveProgram :=
  {|
    ProgState := RDState;
    ProgMem := Z;
    ProgInput := RDInput;
    ProgOutput := Z;
    ProgTransition := RDTrans;
    init_state := RDInit;
    select := fun s _ i =>
      match s, rd_reset i with
      | RDInit, true => TInitReset
      | RDInit, false => TInitData
      | RDRun, true => TRunReset
      | RDRun, false => TRunData
      end;
    enabled := fun t s _ i =>
      match t, s, rd_reset i with
      | TInitReset, RDInit, true => True
      | TInitData, RDInit, false => True
      | TRunReset, RDRun, true => True
      | TRunData, RDRun, false => True
      | _, _, _ => False
      end;
    dst_state := fun _ _ => RDRun;
    upd_mem := fun t _ i =>
      match t with
      | TInitReset | TRunReset => 0
      | TInitData | TRunData => rd_x i
      end;
    out_val := fun t m _ =>
      match t with
      | TRunData => m
      | _ => 0
      end;
    select_enabled := fun s m i =>
      match s, i with
      | RDInit, (true, _) => I
      | RDInit, (false, _) => I
      | RDRun, (true, _) => I
      | RDRun, (false, _) => I
      end
  |}.

(** Assumption automaton states: either the input discipline still holds or it
    has been violated. *)
Inductive RDAssumeState : Type :=
| AOk
| ABad.

(** The assumption says that any asserted reset must come with data value [0]. *)
Definition rd_assume_step (q : RDAssumeState) (i : RDInput) : RDAssumeState :=
  match q with
  | ABad => ABad
  | AOk =>
      if rd_reset i
      then if Z.eq_dec (rd_x i) 0 then AOk else ABad
      else AOk
  end.

Definition rd_assume_automaton : SafetyAutomaton (ProgInput resettable_delay_program).
Proof.
  refine {|
    AutState := RDAssumeState;
    q0 := AOk;
    qbad := ABad;
    qstep := rd_assume_step;
    qeq_dec := _
  |}.
  decide equality.
Defined.

(** Guarantee automaton states. [GAfterData z] remembers the previous relevant
    data value expected on the next ordinary delay step. *)
Inductive RDGuaranteeState : Type :=
| GInit
| GAfterReset
| GAfterData (prev_x : Z)
| GBad.

(** Guarantee transition function encoding the three observable behaviors:
    reset, first non-reset after reset, and ordinary delay. *)
Definition rd_guarantee_step
    (q : RDGuaranteeState)
    (obs : ProgInput resettable_delay_program * ProgOutput resettable_delay_program)
    : RDGuaranteeState :=
  let '(i, y) := obs in
  match q with
  | GBad => GBad
  | GInit =>
      if rd_reset i
      then if Z.eq_dec y 0 then GAfterReset else GBad
      else GAfterData (rd_x i)
  | GAfterReset =>
      if rd_reset i
      then if Z.eq_dec y 0 then GAfterReset else GBad
      else if Z.eq_dec y 0 then GAfterData (rd_x i) else GBad
  | GAfterData z =>
      if rd_reset i
      then if Z.eq_dec y 0 then GAfterReset else GBad
      else if Z.eq_dec y z then GAfterData (rd_x i) else GBad
  end.

Definition rd_guarantee_automaton
  : SafetyAutomaton
      (ProgInput resettable_delay_program * ProgOutput resettable_delay_program).
Proof.
  refine {|
    AutState := RDGuaranteeState;
    q0 := GInit;
    qbad := GBad;
    qstep := rd_guarantee_step;
    qeq_dec := _
  |}.
  decide equality; apply Z.eq_dec.
Defined.

(** Outside the initial state, the guarantee automaton can never jump back to
    [GStart]. This monotonicity fact simplifies the case analysis on later
    executions. *)
Lemma rd_guarantee_step_not_init :
  forall q obs,
    rd_guarantee_step q obs <> GInit.
Proof.
  intros [| |z |] [[r x] y] H;
  destruct r; simpl in H;
  repeat
    match goal with
    | H : context [Z.eq_dec ?a ?b] |- _ => destruct (Z.eq_dec a b)
    end;
  inversion H.
Qed.

(** Concrete conditional specification used for the example. *)
Definition resettable_delay_spec : ConditionalSpec resettable_delay_program.
Proof.
  refine {|
    assume_aut := rd_assume_automaton;
    guarantee_aut := rd_guarantee_automaton;
    assume_init_not_bad := _;
    guarantee_init_not_bad := _
  |}; discriminate.
Defined.

(** User invariant for the example. In steady state, the guarantee automaton
    already summarizes what the current memory means. *)
Definition resettable_delay_node_inv
    (s : ProgState resettable_delay_program)
    (ctx : @TickCtx resettable_delay_program resettable_delay_spec)
    : Prop :=
  match s with
  | RDInit => True
  | RDRun =>
      match cur_guarantee ctx with
      | GAfterReset => cur_mem ctx = 0
      | GAfterData z => cur_mem ctx = z
      | _ => True
      end
  end.

(** After one tick, the control state is necessarily [RDRun]. *)
Lemma rd_state_after_first_tick :
  forall m0 u k,
    state_from resettable_delay_program m0 u (S k) = RDRun.
Proof.
  intros m0 u k.
  unfold state_from.
  rewrite cfg_from_S.
  destruct (cfg_from resettable_delay_program m0 u k) as [s m].
  destruct s, (u k) as [r x]; reflexivity.
Qed.

(** Reset transitions always emit [0]. *)
Lemma rd_out_on_reset :
  forall m0 u k x,
    u k = (true, x) ->
    out_from resettable_delay_program m0 u k = 0.
Proof.
  intros m0 u k x Hu.
  unfold out_from, trans_from.
  destruct (cfg_from resettable_delay_program m0 u k) as [s m].
  destruct s.
  all: rewrite Hu; reflexivity.
Qed.

(** Reset transitions reset the memory to [0]. *)
Lemma rd_mem_after_reset :
  forall m0 u k x,
    u k = (true, x) ->
    mem_from resettable_delay_program m0 u (S k) = 0.
Proof.
  intros m0 u k x Hu.
  unfold mem_from.
  rewrite cfg_from_S.
  destruct (cfg_from resettable_delay_program m0 u k) as [s m].
  destruct s.
  all: rewrite Hu; reflexivity.
Qed.

(** Non-reset data transitions store the current input value into memory. *)
Lemma rd_mem_after_nonreset :
  forall m0 u k x,
    u k = (false, x) ->
    mem_from resettable_delay_program m0 u (S k) = x.
Proof.
  intros m0 u k x Hu.
  unfold mem_from.
  rewrite cfg_from_S.
  destruct (cfg_from resettable_delay_program m0 u k) as [s m].
  destruct s.
  all: rewrite Hu; reflexivity.
Qed.

(** In steady state, an ordinary non-reset transition outputs the current
    memory, hence the previously stored data value. *)
Lemma rd_out_on_nonreset_run :
  forall m0 u k x,
    state_from resettable_delay_program m0 u k = RDRun ->
    u k = (false, x) ->
    out_from resettable_delay_program m0 u k =
    mem_from resettable_delay_program m0 u k.
Proof.
  intros m0 u k x Hstate Hu.
  unfold state_from, out_from, trans_from, mem_from in *.
  destruct (cfg_from resettable_delay_program m0 u k) as [s m] eqn:Hcfg.
  simpl in Hstate.
  destruct s.
  - discriminate.
  - rewrite Hu; reflexivity.
Qed.

(** Main semantic synchronization lemma between the concrete run and the
    guarantee automaton. It explains why the automaton state correctly
    summarizes the meaning of the current memory along admissible runs. *)
Lemma rd_memory_matches_guarantee :
  forall m0 u k,
    match guarantee_state_at resettable_delay_spec m0 u k with
    | GAfterReset => mem_from resettable_delay_program m0 u k = 0
    | GAfterData z => mem_from resettable_delay_program m0 u k = z
    | _ => True
    end.
Proof.
  intros m0 u k.
  induction k as [|k IH].
  - simpl. exact I.
  - remember (guarantee_state_at resettable_delay_spec m0 u k) as gk eqn:Hgk.
    destruct gk as [| |z |].
    + unfold guarantee_state_at in Hgk. simpl in Hgk.
      destruct (u k) as [r x] eqn:Hu.
      destruct r; simpl in *.
      * destruct (Z.eq_dec (out_from resettable_delay_program m0 u k) 0) as [Hz|Hz].
        -- unfold guarantee_state_at. simpl. rewrite <- Hgk, Hu, Hz. simpl.
           destruct (Z.eq_dec 0 0) as [_|Hneq]; [|contradiction].
           apply rd_mem_after_reset with (x := x). exact Hu.
        -- unfold guarantee_state_at. simpl. rewrite <- Hgk, Hu. simpl.
           destruct (Z.eq_dec (out_from resettable_delay_program m0 u k) 0); [contradiction|exact I].
      * unfold guarantee_state_at. simpl. rewrite <- Hgk, Hu. simpl.
        apply rd_mem_after_nonreset with (x := x). exact Hu.
    + unfold guarantee_state_at in Hgk. simpl in Hgk.
      destruct (u k) as [r x] eqn:Hu.
      destruct r; simpl in *.
      * destruct (Z.eq_dec (out_from resettable_delay_program m0 u k) 0) as [Hz|Hz].
        -- unfold guarantee_state_at. simpl. rewrite <- Hgk, Hu, Hz. simpl.
           destruct (Z.eq_dec 0 0) as [_|Hneq]; [|contradiction].
           apply rd_mem_after_reset with (x := x). exact Hu.
        -- unfold guarantee_state_at. simpl. rewrite <- Hgk, Hu. simpl.
           destruct (Z.eq_dec (out_from resettable_delay_program m0 u k) 0); [contradiction|exact I].
      * destruct (Z.eq_dec (out_from resettable_delay_program m0 u k) 0) as [Hz|Hz].
        -- unfold guarantee_state_at. simpl. rewrite <- Hgk, Hu, Hz. simpl.
           destruct (Z.eq_dec 0 0) as [_|Hneq]; [|contradiction].
           apply rd_mem_after_nonreset with (x := x). exact Hu.
        -- unfold guarantee_state_at. simpl. rewrite <- Hgk, Hu. simpl.
           destruct (Z.eq_dec (out_from resettable_delay_program m0 u k) 0); [contradiction|exact I].
    + unfold guarantee_state_at in Hgk. simpl in Hgk.
      destruct (u k) as [r x] eqn:Hu.
      destruct r; simpl in *.
      * destruct (Z.eq_dec (out_from resettable_delay_program m0 u k) 0) as [Hz|Hz].
        -- unfold guarantee_state_at. simpl. rewrite <- Hgk, Hu, Hz. simpl.
           destruct (Z.eq_dec 0 0) as [_|Hneq]; [|contradiction].
           apply rd_mem_after_reset with (x := x). exact Hu.
        -- unfold guarantee_state_at. simpl. rewrite <- Hgk, Hu. simpl.
           destruct (Z.eq_dec (out_from resettable_delay_program m0 u k) 0); [contradiction|exact I].
      * destruct (Z.eq_dec (out_from resettable_delay_program m0 u k) z) as [Hz|Hz].
        -- unfold guarantee_state_at. simpl. rewrite <- Hgk, Hu, Hz. simpl.
           destruct (Z.eq_dec z z) as [_|Hneq]; [|contradiction].
           apply rd_mem_after_nonreset with (x := x). exact Hu.
        -- unfold guarantee_state_at. simpl. rewrite <- Hgk, Hu. simpl.
           destruct (Z.eq_dec (out_from resettable_delay_program m0 u k) z); [contradiction|exact I].
    + unfold guarantee_state_at in Hgk |- *. simpl in Hgk |- *.
      rewrite <- Hgk. simpl. exact I.
Qed.

(** Semantic truth of the user invariant on admissible runs. *)
Lemma resettable_delay_node_inv_on_runs :
  forall m0 u k,
    resettable_delay_node_inv
      (state_from resettable_delay_program m0 u k)
      (@ctx_from resettable_delay_program resettable_delay_spec m0 u k).
Proof.
  intros m0 u k.
  unfold resettable_delay_node_inv, ctx_from.
  simpl.
  destruct (state_from resettable_delay_program m0 u k).
  - exact I.
  - destruct (guarantee_state_at resettable_delay_spec m0 u k) as [| |z |] eqn:Hg; simpl; auto.
    + pose proof (rd_memory_matches_guarantee m0 u k) as Hmem.
      rewrite Hg in Hmem. exact Hmem.
    + pose proof (rd_memory_matches_guarantee m0 u k) as Hmem.
      rewrite Hg in Hmem. exact Hmem.
Qed.

(** Direct semantic safety fact for the guarantee automaton along admissible
    runs. This lemma is used internally to justify the generated safety
    triples, not as the final proof style exposed to the user. *)
Lemma rd_guarantee_safe :
  forall m0 u k,
    guarantee_state_at resettable_delay_spec m0 u k <> GBad.
Proof.
  intros m0 u k.
  induction k as [|k IH].
  - simpl. discriminate.
  - remember (guarantee_state_at resettable_delay_spec m0 u k) as gk eqn:Hgk.
    destruct gk as [| |z |].
    + unfold guarantee_state_at in Hgk. simpl in Hgk.
      destruct (u k) as [r x] eqn:Hu.
      destruct r.
      * assert (Hout : out_from resettable_delay_program m0 u k = 0).
        { apply rd_out_on_reset with (x := x). exact Hu. }
        unfold guarantee_state_at. simpl. rewrite <- Hgk, Hu, Hout. simpl.
        destruct (Z.eq_dec 0 0) as [_|Hneq]; [discriminate|contradiction].
      * unfold guarantee_state_at. simpl. rewrite <- Hgk, Hu. simpl. discriminate.
    + unfold guarantee_state_at in Hgk. simpl in Hgk.
      destruct (u k) as [r x] eqn:Hu.
      destruct r.
      * assert (Hout : out_from resettable_delay_program m0 u k = 0).
        { apply rd_out_on_reset with (x := x). exact Hu. }
        unfold guarantee_state_at. simpl. rewrite <- Hgk, Hu, Hout. simpl.
        destruct (Z.eq_dec 0 0) as [_|Hneq]; [discriminate|contradiction].
      * assert (Hstate : state_from resettable_delay_program m0 u k = RDRun).
        { destruct k as [|k'].
          - simpl in Hgk. discriminate.
          - apply rd_state_after_first_tick. }
        assert (Hout :
          out_from resettable_delay_program m0 u k =
          mem_from resettable_delay_program m0 u k).
        { apply rd_out_on_nonreset_run with (x := x); assumption. }
        pose proof (rd_memory_matches_guarantee m0 u k) as Hmem.
        unfold guarantee_state_at in Hmem. simpl in Hmem.
        rewrite <- Hgk in Hmem. simpl in Hmem.
        rewrite Hmem in Hout.
        unfold guarantee_state_at. simpl. rewrite <- Hgk, Hu, Hout. simpl.
        destruct (Z.eq_dec 0 0) as [_|Hneq]; [discriminate|contradiction].
    + unfold guarantee_state_at in Hgk. simpl in Hgk.
      destruct (u k) as [r x] eqn:Hu.
      destruct r.
      * assert (Hout : out_from resettable_delay_program m0 u k = 0).
        { apply rd_out_on_reset with (x := x). exact Hu. }
        unfold guarantee_state_at. simpl. rewrite <- Hgk, Hu, Hout. simpl.
        destruct (Z.eq_dec 0 0) as [_|Hneq]; [discriminate|contradiction].
      * assert (Hstate : state_from resettable_delay_program m0 u k = RDRun).
        { destruct k as [|k'].
          - simpl in Hgk. discriminate.
          - apply rd_state_after_first_tick. }
        assert (Hout :
          out_from resettable_delay_program m0 u k =
          mem_from resettable_delay_program m0 u k).
        { apply rd_out_on_nonreset_run with (x := x); assumption. }
        pose proof (rd_memory_matches_guarantee m0 u k) as Hmem.
        unfold guarantee_state_at in Hmem. simpl in Hmem.
        rewrite <- Hgk in Hmem. simpl in Hmem.
        rewrite Hmem in Hout.
        unfold guarantee_state_at. simpl. rewrite <- Hgk, Hu, Hout. simpl.
        destruct (Z.eq_dec z z) as [_|Hneq]; [discriminate|contradiction].
    + contradiction.
Qed.

(** Concrete version of the general uniqueness lemma for current coherence. *)
Lemma rd_coherence_now_exact :
  forall m0 u k st,
    coherence_now st (@ctx_from resettable_delay_program resettable_delay_spec m0 u k) ->
    st =
      @product_state_from
        resettable_delay_program resettable_delay_spec m0 u k.
Proof.
  intros m0 u k [sp sa sg] [Hs [Ha Hg]].
  simpl in *.
  subst; reflexivity.
Qed.

(** Concrete version of the abstract fact that a well-formed matched step with
    coherent source must target the next concrete product state. *)
Lemma rd_target_is_next_state :
  forall m0 u k ps,
    product_step_wf ps ->
    ctx_matches_ps (@ctx_from resettable_delay_program resettable_delay_spec m0 u k) ps ->
    coherence_now (pst_from ps) (@ctx_from resettable_delay_program resettable_delay_spec m0 u k) ->
    pst_target ps =
      @product_state_from
        resettable_delay_program resettable_delay_spec m0 u (S k).
Proof.
  intros m0 u k [src t m i o tgt] Hwf Hmatch Hcoh.
  simpl in *.
  destruct src as [sp sa sg].
  simpl in *.
  destruct Hmatch as [Hs [Hm [Hi [Ho Ht]]]].
  destruct Hcoh as [Hsp [Hsa Hsg]].
  simpl in Hs, Hm, Hi, Ho, Ht, Hsp, Hsa, Hsg.
  subst.
  unfold product_step_wf in Hwf.
  simpl in Hwf.
  rewrite Hwf.
  unfold product_step_target_of.
  simpl.
  unfold product_state_from, state_from, trans_from,
    assume_state_at, guarantee_state_at, trace_from.
  rewrite cfg_from_S.
  remember (cfg_from resettable_delay_program m0 u k) as cfg eqn:Hcfg.
  destruct cfg as [s mcur].
  simpl.
  reflexivity.
Qed.

(** Every generated triple for the concrete instance is semantically valid. This
    is the local-proof side of the instantiation. *)
Theorem resettable_delay_generated_triples_valid :
  forall ht : @RelHoareTriple resettable_delay_program resettable_delay_spec,
    @GeneratedTriple
      resettable_delay_program
      resettable_delay_spec
      resettable_delay_node_inv
      ht ->
    @TripleValid resettable_delay_program resettable_delay_spec ht.
Proof.
  intros ht [o Hgen].
  destruct Hgen.
  - simpl.
    intros ctx [m0 [u Hctx]] _.
    subst; exact I.
  - simpl.
    intros ctx [m0 [u Hctx]] _.
    subst; repeat split; reflexivity.
  - simpl.
    intros ctx ctx' [m0 [u [k [Hctx [Hctx' Ht]]]]] [Hmatch [Hinv Hcoh]].
    subst ctx ctx'.
    change
      (resettable_delay_node_inv
         (ps_prog (pst_target ps))
         (@ctx_from resettable_delay_program resettable_delay_spec m0 u (S k))).
    rewrite
      (rd_target_is_next_state
         (m0 := m0) (u := u) (k := k) (ps := ps) H Hmatch Hcoh).
    apply resettable_delay_node_inv_on_runs.
  - simpl.
    intros ctx ctx' [m0 [u [k [Hctx [Hctx' Ht]]]]] [Hmatch Hcoh].
    subst ctx ctx'.
    unfold automaton_coherence_clause.
    change
      (coherence_now
         (pst_target ps)
         (@ctx_from resettable_delay_program resettable_delay_spec m0 u (S k))).
    rewrite
      (rd_target_is_next_state
         (m0 := m0) (u := u) (k := k) (ps := ps) H Hmatch Hcoh).
    exact
      (@coherence_now_from_run
         resettable_delay_program resettable_delay_spec m0 u (S k)).
  - simpl.
    intros ctx ctx' [m0 [u [k [Hctx [Hctx' Ht]]]]] [Hmatch [Hinv Hcoh]].
    subst ctx ctx'.
    destruct H0 as [Hgbad _].
    rewrite
      (rd_target_is_next_state
         (m0 := m0) (u := u) (k := k) (ps := ps) H Hmatch Hcoh)
      in Hgbad.
    exact (rd_guarantee_safe m0 u (S k) Hgbad).
Qed.

(** Final correctness theorem for the example. The proof deliberately goes
    through the abstract soundness theorem rather than a direct trace argument. *)
Theorem resettable_delay_correct :
  forall u,
    AvoidA resettable_delay_spec u ->
    AvoidG resettable_delay_spec u.
Proof.
  exact
    (@validation_conditional_correctness
       resettable_delay_program
       resettable_delay_spec
       resettable_delay_node_inv
       resettable_delay_generated_triples_valid
       (fun m0 u k _ => resettable_delay_node_inv_on_runs m0 u k)).
Qed.
