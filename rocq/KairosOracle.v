From Stdlib Require Import Arith.Arith.
From Stdlib Require Import Bool.Bool.
From Stdlib Require Import Logic.Classical.
From Stdlib Require Import Lists.List.
Import ListNotations.

Set Implicit Arguments.

Module KairosOracleModel.

(* -------------------------------------------------------------------------- *)
(* Vue d'ensemble                                                             *)
(* -------------------------------------------------------------------------- *)
(* Ce module formalise une preuve conditionnelle de correction:
   - un programme synchrone (automate de contrôle + mémoire),
   - deux automates de sûreté (hypothèse A sur entrées, garantie G sur I/O),
   - des obligations locales générées depuis des pas du produit,
   - un oracle qui valide ces obligations.

   Théorème final:
     avoids_bad_A u -> avoids_bad_G (run_trace u)
   pour tout flux d'entrée u. *)

(* Les flux infinis sont modélisés extensionnellement par nat -> A. *)
Definition stream (A : Type) : Type := nat -> A.

Section Model.

  Variable InputVal OutputVal Mem State : Type.

  (* Résultat d'un pas synchrone du programme. *)
  Record StepResult : Type := {
    st_next : State;
    mem_next : Mem;
    out_cur : OutputVal;
  }.

  (* Automate explicite du programme Kairos:
     - état de contrôle,
     - garde de transition,
     - mise à jour mémoire,
     - sortie du tick courant. *)
  Record ProgramAutomaton : Type := {
    Trans : Type;
    src_of : Trans -> State;
    dst_of : Trans -> State;
    guard_of : Trans -> Mem -> InputVal -> Prop;
    upd_of : Trans -> Mem -> InputVal -> Mem;
    out_of : Trans -> Mem -> InputVal -> OutputVal;
  }.

  Variable Paut : ProgramAutomaton.

  (* t est activée dans le contexte courant (s,m,i). *)
  Definition trans_enabled (t : Trans Paut) (s : State) (m : Mem) (i : InputVal) : Prop :=
    src_of Paut t = s /\ guard_of Paut t m i.

  (* Effet sémantique d'une transition t sur (m,i). *)
  Definition trans_result (t : Trans Paut) (m : Mem) (i : InputVal) : StepResult :=
    {|
      st_next := dst_of Paut t;
      mem_next := upd_of Paut t m i;
      out_cur := out_of Paut t m i;
    |}.

  (* Sélecteur déterministe de transition.
     Hypothèse minimale: la transition sélectionnée est bien activée. *)
  Variable prog_select : State -> Mem -> InputVal -> Trans Paut.
  Hypothesis prog_select_enabled :
    forall s m i, trans_enabled (prog_select s m i) s m i.
  (* Sémantique "fonctionnelle" du pas programme, dérivée de prog_select. *)
  Definition step (s : State) (m : Mem) (i : InputVal) : StepResult :=
    trans_result (prog_select s m i) m i.
  Variable init_state : State.
  Variable init_mem : Mem.
  Variable node_inv : State -> Mem -> Prop.
  Hypothesis node_inv_init :
    node_inv init_state init_mem.
  Hypothesis node_inv_preserved :
    forall s m i,
      node_inv s m ->
      let r := step s m i in
      node_inv (st_next r) (mem_next r).

  (* Trace observable au tick k = entrée courante + sortie produite. *)
  Definition io_val : Type := InputVal * OutputVal.

  (* Configuration interne atteinte au début du tick k. *)
  Fixpoint cfg_at (u : stream InputVal) (k : nat) : State * Mem :=
    match k with
    | O => (init_state, init_mem)
    | S n =>
        let '(s, m) := cfg_at u n in
        let r := step s m (u n) in
        (st_next r, mem_next r)
    end.

  Lemma node_inv_cfg_at :
    forall u k,
      let '(s, m) := cfg_at u k in
      node_inv s m.
  Proof.
    intros u k.
    induction k as [|n IH].
    - simpl. exact node_inv_init.
    - simpl.
      destruct (cfg_at u n) as [s m] eqn:Hcfg.
      simpl in IH.
      eapply node_inv_preserved.
      exact IH.
  Qed.

  (* Pas exécuté au tick k. *)
  Definition step_at (u : stream InputVal) (k : nat) : StepResult :=
    let '(s, m) := cfg_at u k in
    step s m (u k).

  (* Sortie observée au tick k. *)
  Definition out_at (u : stream InputVal) (k : nat) : OutputVal :=
    out_cur (step_at u k).

  (* Trace I/O complète produite par le programme. *)
  Definition run_trace (u : stream InputVal) : stream io_val :=
    fun k => (u k, out_at u k).

  (* Automate de sûreté standard (vue fonctionnelle). *)
  Record SafetyAutomaton (Obs : Type) : Type := {
    q : Type;
    q0 : q;
    bad : q;
    delta : q -> Obs -> q;
  }.

  Arguments q {_}.
  Arguments q0 {_}.
  Arguments bad {_}.
  Arguments delta {_}.

  (* État de l'automate après k pas sur la trace w. *)
  Fixpoint aut_state_at {Obs : Type} (A : SafetyAutomaton Obs) (w : stream Obs) (k : nat)
      : q A :=
    match k with
    | O => q0 A
    | S n => delta A (aut_state_at A w n) (w n)
    end.

  (* Critère d'acceptation de sûreté: on n'atteint jamais bad. *)
  Definition avoids_bad {Obs : Type} (A : SafetyAutomaton Obs) (w : stream Obs) : Prop :=
    forall k, aut_state_at A w k <> bad A.

  (* Version "arêtes + labels FO" des automates de sûreté.
     Les labels FO sont encodés directement en logique Rocq: Obs -> Prop. *)
  Definition FOLabel (Obs : Type) : Type := Obs -> Prop.

  Record SafetyAutomatonEdges (Obs : Type) (A : SafetyAutomaton Obs) : Type := {
    Edge : Type;
    src_e : Edge -> q A;
    dst_e : Edge -> q A;
    label_e : Edge -> FOLabel Obs;
  }.

  Arguments Edge {_ _}.
  Arguments src_e {_ _}.
  Arguments dst_e {_ _}.
  Arguments label_e {_ _}.

  (* Une arête est activée si elle part de l'état courant et son label est vrai. *)
  Definition edge_enabled {Obs : Type} {A : SafetyAutomaton Obs} (AE : SafetyAutomatonEdges A)
      (e : Edge AE) (qv : q A)
      (obs : Obs) : Prop :=
    src_e AE e = qv /\ label_e AE e obs.

  (* Automates d'hypothèse (entrées) et de garantie (I/O). *)
  Variable A_aut : SafetyAutomaton InputVal.
  Variable G_aut : SafetyAutomaton io_val.
  Variable A_aut_e : SafetyAutomatonEdges A_aut.
  Variable G_aut_e : SafetyAutomatonEdges G_aut.

  (* Sélecteurs déterministes d'arêtes automates.
     On impose:
       - la source est bien l'état courant,
       - le label FO de l'arête choisie est vrai sur l'observation courante. *)
  Variable select_A : q A_aut -> InputVal -> Edge A_aut_e.
  Variable select_G : q G_aut -> io_val -> Edge G_aut_e.
  Hypothesis select_A_src :
    forall qa i, src_e A_aut_e (select_A qa i) = qa.
  Hypothesis select_G_src :
    forall qg io, src_e G_aut_e (select_G qg io) = qg.
  Hypothesis select_A_label :
    forall qa i, label_e A_aut_e (select_A qa i) i.
  Hypothesis select_G_label :
    forall qg io, label_e G_aut_e (select_G qg io) io.

  (* Deltas dérivés des arêtes sélectionnées. *)
  Definition delta_A (qa : q A_aut) (i : InputVal) : q A_aut :=
    dst_e A_aut_e (select_A qa i).
  Definition delta_G (qg : q G_aut) (io : io_val) : q G_aut :=
    dst_e G_aut_e (select_G qg io).

  (* États automates le long d'une exécution.
     Ces définitions sont celles utilisées dans tout le reste du développement. *)
  Fixpoint aut_state_at_A (u : stream InputVal) (k : nat) : q A_aut :=
    match k with
    | O => q0 A_aut
    | S n => delta_A (aut_state_at_A u n) (u n)
    end.

  Fixpoint aut_state_at_G (w : stream io_val) (k : nat) : q G_aut :=
    match k with
    | O => q0 G_aut
    | S n => delta_G (aut_state_at_G w n) (w n)
    end.

  (* Propriétés de sûreté "automates-only". *)
  Definition avoids_bad_A (u : stream InputVal) : Prop :=
    forall k, aut_state_at_A u k <> bad A_aut.
  Definition avoids_bad_G (w : stream io_val) : Prop :=
    forall k, aut_state_at_G w k <> bad G_aut.

  (* -------------------------------------------------------------------------- *)
  (* Automate produit synchrone                                                 *)
  (* -------------------------------------------------------------------------- *)
  (* État du produit = (état programme, état A, état G). *)
  Record ProductState : Type := {
    ps_prog : State;
    ps_a : q A_aut;
    ps_g : q G_aut;
  }.

  (* Un pas candidat du produit transporte:
     - l'état source produit,
     - la transition programme,
     - l'arête A, l'arête G,
     - le contexte mémoire/entrée du pas. *)
  Record ProductStep : Type := {
    pst_from : ProductState;
    pst_trans : Trans Paut;
    pst_a_edge : Edge A_aut_e;
    pst_g_edge : Edge G_aut_e;
    pst_mem : Mem;
    pst_in : InputVal;
  }.

  (* Observation I/O associée à une transition programme dans un contexte (m,i). *)
  Definition product_obs_io (t : Trans Paut) (m : Mem) (i : InputVal) : io_val :=
    (i, out_of Paut t m i).

  (* Pas du produit bien formé:
     - transition programme activée,
     - arêtes A/G activées,
     - cibles cohérentes avec delta_A/delta_G. *)
  Definition product_step_wf (ps : ProductStep) : Prop :=
    let st := pst_from ps in
    let t := pst_trans ps in
    let ea := pst_a_edge ps in
    let eg := pst_g_edge ps in
    let m := pst_mem ps in
    let i := pst_in ps in
    trans_enabled t (ps_prog st) m i
    /\ edge_enabled A_aut_e ea (ps_a st) i
    /\ edge_enabled G_aut_e eg (ps_g st) (product_obs_io t m i)
    /\ dst_e A_aut_e ea = delta_A (ps_a st) i
    /\ dst_e G_aut_e eg = delta_G (ps_g st) (product_obs_io t m i).

  (* État cible d'un pas du produit. *)
  Definition product_step_target (ps : ProductStep) : ProductState :=
    let st := pst_from ps in
    let t := pst_trans ps in
    let ea := pst_a_edge ps in
    let eg := pst_g_edge ps in
    {|
      ps_prog := dst_of Paut t;
      ps_a := dst_e A_aut_e ea;
      ps_g := dst_e G_aut_e eg;
    |}.

  (* Cible "dangereuse" pour G (tout en restant hors bad_A). *)
  Definition product_step_is_bad_target (ps : ProductStep) : Prop :=
    let st' := product_step_target ps in
    ps_a st' <> bad A_aut /\ ps_g st' = bad G_aut.

  (* Cible sûre (hors bad_A et hors bad_G). *)
  Definition product_step_is_safe_target (ps : ProductStep) : Prop :=
    let st' := product_step_target ps in
    ps_a st' <> bad A_aut /\ ps_g st' <> bad G_aut.

  (* Automata-only mode: assumptions/guarantees are directly
     expressed as "avoid bad" on the given safety automata. *)

  (* -------------------------------------------------------------------------- *)
  (* Obligations de preuve locales                                              *)
  (* -------------------------------------------------------------------------- *)
  (* Le contexte local d'un pas concret observé dans l'exécution du programme. *)
  Record StepCtx : Type := {
    tick : nat;
    cur_state : State;
    cur_mem : Mem;
    cur_input : InputVal;
    next_state : State;
    next_mem : Mem;
    cur_output : OutputVal;
  }.

  (* Contexte au tick k pour le flux u. *)
  Definition ctx_at (u : stream InputVal) (k : nat) : StepCtx :=
    let '(s, m) := cfg_at u k in
    let r := step s m (u k) in
    {|
      tick := k;
      cur_state := s;
      cur_mem := m;
      cur_input := u k;
      next_state := st_next r;
      next_mem := mem_next r;
      cur_output := out_cur r;
    |}.

  (* Une obligation est un prédicat logique sur un contexte local.
     ObligationValid = vraie pour tous les ticks de toutes les exécutions. *)
  Definition Obligation : Type := StepCtx -> Prop.
  Definition ObligationValid (obl : Obligation) : Prop :=
    forall u k, obl (ctx_at u k).

  (* -------------------------------------------------------------------------- *)
  (* Décalage abstrait des formules FO                                          *)
  (* -------------------------------------------------------------------------- *)
  (* Cette couche formalise abstraitement la transformation temporelle utilisée
     en implémentation (shift), sans exposer la syntaxe des opérateurs
     d'historique. *)
  Variable FO : Type.
  Variable eval_fo : StepCtx -> FO -> Prop.
  Variable shift_fo : nat -> FO -> FO.

  (* Admissibilité d'entrée au tick k: l'automate d'hypothèse n'est pas en bad. *)
  Definition InputOk (u : stream InputVal) (k : nat) : Prop :=
    aut_state_at_A u k <> bad A_aut.

  Lemma avoids_bad_A_implies_InputOk :
    forall u, avoids_bad_A u -> forall k, InputOk u k.
  Proof.
    intros u HA k.
    unfold InputOk, avoids_bad_A in *.
    exact (HA k).
  Qed.

  (* Correction conditionnelle de la transformation:
     sous admissibilité d'entrée, évaluer [shift_fo d phi] au tick k revient
     à évaluer [phi] au tick k+d. *)
  Hypothesis shift_fo_correct_if_input_ok :
    forall d u k phi,
      InputOk u k ->
      eval_fo (ctx_at u k) (shift_fo d phi) <-> eval_fo (ctx_at u (k + d)) phi.

  Lemma shift_fo_correct_one_step :
    forall u k phi,
      InputOk u k ->
      eval_fo (ctx_at u k) (shift_fo 1 phi) <-> eval_fo (ctx_at u (S k)) phi.
  Proof.
    intros u k phi Hok.
    rewrite shift_fo_correct_if_input_ok by exact Hok.
    rewrite Nat.add_1_r.
    reflexivity.
  Qed.

  Theorem shifted_formula_transfers_to_successor :
    forall u k phi,
      InputOk u k ->
      eval_fo (ctx_at u k) (shift_fo 1 phi) ->
      eval_fo (ctx_at u (S k)) phi.
  Proof.
    intros u k phi Hok H.
    assert (Hshift :
      eval_fo (ctx_at u k) (shift_fo 1 phi) <-> eval_fo (ctx_at u (k + 1)) phi).
    { apply shift_fo_correct_if_input_ok. exact Hok. }
    rewrite Nat.add_1_r in Hshift.
    exact ((proj1 Hshift) H).
  Qed.

  (* Origine/provenance d'une obligation générée. *)
  Inductive origin : Type :=
  | UserContract
  | Coherency
  | Compatibility
  | AssumeAutomaton
  | Instrumentation
  | NodeInvariant
  | Internal.

  Definition generated_item : Type := origin * Obligation.

  (* Classification des obligations issues d'un pas produit (paramètre). *)
  Variable classify_product_step : ProductStep -> origin.

  (* Le contexte concret "matche" un pas produit donné. *)
  Definition ctx_matches_ps (ctx : StepCtx) (ps : ProductStep) : Prop :=
    cur_state ctx = ps_prog (pst_from ps)
    /\ cur_mem ctx = pst_mem ps
    /\ cur_input ctx = pst_in ps
    /\ trans_enabled (pst_trans ps) (cur_state ctx) (cur_mem ctx) (cur_input ctx).

  (* Obligation canonique issue d'un pas produit:
     interdire que le contexte concret matche ce pas. *)
  Definition prod_obligation (ps : ProductStep) : Obligation :=
    fun ctx => ~ ctx_matches_ps ctx ps.

  (* Obligation de cohérence d'invariant de nœud:
     dès qu'un contexte matche ps, l'invariant de nœud courant doit tenir. *)
  Definition node_inv_obligation (ps : ProductStep) : Obligation :=
    fun ctx => ctx_matches_ps ctx ps -> node_inv (cur_state ctx) (cur_mem ctx).

  (* Génération locale depuis un pas produit. *)
  Definition gen_from_product_step (ps : ProductStep) : list generated_item :=
    [ (classify_product_step ps, prod_obligation ps);
      (NodeInvariant, node_inv_obligation ps) ].

  (* Relation de génération (niveau preuve):
     l'obligation est générée depuis un pas produit bien formé. *)
  Inductive GeneratedBy : origin -> Trans Paut -> Obligation -> Prop :=
  | GeneratedBy_product :
      forall o t obl ps,
        product_step_wf ps ->
        pst_trans ps = t ->
        In (o, obl) (gen_from_product_step ps) ->
        GeneratedBy o t obl
  .

  (* Ensemble des obligations générées (oubliant origine/transition). *)
  Definition Generated (obl : Obligation) : Prop :=
    exists o t, GeneratedBy o t obl.

  (* -------------------------------------------------------------------------- *)
  (* Exécution du produit le long d'un run programme                            *)
  (* -------------------------------------------------------------------------- *)
  Definition run_product_state (u : stream InputVal) (k : nat) : ProductState :=
    let '(s, _m) := cfg_at u k in
    {|
      ps_prog := s;
      ps_a := aut_state_at_A u k;
      ps_g := aut_state_at_G (run_trace u) k;
    |}.

  (* Invariants "jamais bad" si la propriété avoids_bad correspondante tient. *)
  Theorem no_bad_A_invariant :
    forall u, avoids_bad_A u -> forall k, ps_a (run_product_state u k) <> bad A_aut.
  Proof.
    intros u HA k.
    unfold run_product_state.
    destruct (cfg_at u k) as [s m].
    simpl.
    apply (HA k).
  Qed.

  Theorem no_bad_G_invariant :
    forall u, avoids_bad_G (run_trace u) -> forall k, ps_g (run_product_state u k) <> bad G_aut.
  Proof.
    intros u HG k.
    unfold run_product_state.
    destruct (cfg_at u k) as [s m].
    simpl.
    apply (HG k).
  Qed.

  (* -------------------------------------------------------------------------- *)
  (* Oracle                                                                      *)
  (* -------------------------------------------------------------------------- *)
  (* Soundness: si oracle dit true alors l'obligation est sémantiquement valide.
     Complete: toutes les obligations générées sont validées par l'oracle. *)
  Variable Oracle : Obligation -> bool.
  Hypothesis Oracle_sound :
    forall obl, Oracle obl = true -> ObligationValid obl.
  Hypothesis Oracle_complete :
    forall obl, Generated obl -> Oracle obl = true.

  (* Ce que signifie "le pas produit ps est celui effectivement réalisé au tick k". *)
  Definition product_step_realizes_at (u : stream InputVal) (k : nat) (ps : ProductStep) : Prop :=
    let '(s, m) := cfg_at u k in
    pst_from ps = run_product_state u k
    /\ pst_mem ps = m
    /\ pst_in ps = u k
    /\ pst_trans ps = prog_select s m (u k).

  (* Conditions de base: états initiaux A/G non mauvais. *)
  Hypothesis A_init_not_bad : q0 A_aut <> bad A_aut.
  Hypothesis G_init_not_bad : q0 G_aut <> bad G_aut.

  (* Pas local dangereux: il existe un pas produit réalisé, bien formé,
     dont la cible est bad_G et non bad_A. *)
  Definition bad_local_step (u : stream InputVal) (k : nat) : Prop :=
    exists ps,
      product_step_wf ps
      /\ product_step_realizes_at u k ps
      /\ product_step_is_bad_target ps.

  (* Existence d'un pas produit réalisé à tout tick (construction explicite). *)
  Lemma realizable_product_step :
    forall u k, exists ps, product_step_wf ps /\ product_step_realizes_at u k ps.
  Proof.
    intros u k.
    destruct (cfg_at u k) as [s m] eqn:Hcfg.
    set (t := prog_select s m (u k)).
    set (qa := aut_state_at_A u k).
    set (qg := aut_state_at_G (run_trace u) k).
    set (ea := select_A qa (u k)).
    set (obsg := product_obs_io t m (u k)).
    set (eg := select_G qg obsg).
    exists
      {|
        pst_from := run_product_state u k;
        pst_trans := t;
        pst_a_edge := ea;
        pst_g_edge := eg;
        pst_mem := m;
        pst_in := u k;
      |}.
    split.
    - unfold product_step_wf.
      simpl.
      split.
      + unfold run_product_state.
        rewrite Hcfg.
        simpl.
        apply prog_select_enabled.
      + split.
        * unfold run_product_state.
          rewrite Hcfg.
          simpl.
          unfold edge_enabled.
          split.
          -- apply select_A_src.
          -- apply select_A_label.
        * split.
          -- unfold run_product_state.
             rewrite Hcfg.
             simpl.
             unfold edge_enabled.
             split.
             ++ apply select_G_src.
             ++ apply select_G_label.
          -- split.
             ++ unfold run_product_state.
                rewrite Hcfg.
                simpl.
                reflexivity.
             ++ unfold run_product_state.
                rewrite Hcfg.
                simpl.
                reflexivity.
    - unfold product_step_realizes_at.
      rewrite Hcfg.
      split; [reflexivity |].
      split; [reflexivity |].
      split; [reflexivity |].
      reflexivity.
  Qed.

  (* Correction de projection cible:
     la cible du pas produit coïncide avec les états automates au tick suivant. *)
  Lemma realized_step_target_correct :
    forall u k ps,
      product_step_wf ps ->
      product_step_realizes_at u k ps ->
      ps_a (product_step_target ps) = aut_state_at_A u (S k)
      /\ ps_g (product_step_target ps) = aut_state_at_G (run_trace u) (S k).
  Proof.
    intros u k ps Hwf Hreal.
    unfold product_step_realizes_at in Hreal.
    destruct (cfg_at u k) as [s m] eqn:Hcfg.
    destruct Hreal as [Hfrom [Hmem [Hin Htr]]].
    unfold product_step_wf in Hwf.
    destruct Hwf as [Hen [Hea [Heg [HdstA HdstG]]]].
    unfold product_step_target.
    split.
    - simpl.
      pose proof (f_equal ps_a Hfrom) as Ha_from.
      unfold run_product_state in Ha_from.
      rewrite Hcfg in Ha_from.
      simpl in Ha_from.
      rewrite HdstA.
      rewrite Ha_from.
      rewrite Hin.
      reflexivity.
    - simpl.
      pose proof (f_equal ps_g Hfrom) as Hg_from.
      unfold run_product_state in Hg_from.
      rewrite Hcfg in Hg_from.
      simpl in Hg_from.
      rewrite HdstG.
      rewrite Hg_from.
      rewrite Hin.
      unfold run_trace.
      unfold product_obs_io.
      rewrite Htr.
      rewrite Hmem.
      unfold out_at, step_at, step.
      rewrite Hcfg.
      reflexivity.
  Qed.

  (* Si G est violée globalement (sur run_trace), alors il existe un tick local dangereux. *)
  Theorem bad_local_step_if_G_violated :
    forall u, avoids_bad_A u -> ~ avoids_bad_G (run_trace u) -> exists k, bad_local_step u k.
  Proof.
    intros u HA HnG.
    unfold avoids_bad in HnG.
    apply not_all_ex_not in HnG.
    destruct HnG as [j Hj].
    assert (Hjbad : aut_state_at_G (run_trace u) j = bad G_aut).
    { apply NNPP. exact Hj. }
    destruct j as [|k].
    - exfalso.
      simpl in Hjbad.
      exact (G_init_not_bad Hjbad).
    - destruct (realizable_product_step u k) as [ps [Hwf Hreal]].
      exists k.
      unfold bad_local_step.
      exists ps.
      split; [exact Hwf |].
      split; [exact Hreal |].
      unfold product_step_is_bad_target.
      pose proof (@realized_step_target_correct u k ps Hwf Hreal) as [Ha Hg].
      split.
      + rewrite Ha.
        apply HA.
      + rewrite Hg.
        exact Hjbad.
  Qed.

  (* Un pas produit réalisé se reflète bien dans le contexte concret ctx_at. *)
  Lemma ctx_at_matches_realized_ps :
    forall u k ps,
      product_step_wf ps ->
      product_step_realizes_at u k ps ->
      ctx_matches_ps (ctx_at u k) ps.
  Proof.
    intros u k ps Hwf Hreal.
    unfold product_step_realizes_at in Hreal.
    destruct (cfg_at u k) as [s m] eqn:Hcfg.
    destruct Hreal as [Hfrom [Hmem [Hin _Htr]]].
    pose proof (f_equal ps_prog Hfrom) as Hprog.
    unfold run_product_state in Hprog.
    rewrite Hcfg in Hprog.
    simpl in Hprog.
    unfold ctx_matches_ps, ctx_at.
    rewrite Hcfg.
    simpl in *.
    destruct Hwf as [Hen _].
    destruct Hen as [Hsrc Hguard].
    split; [symmetry; exact Hprog |].
    split; [symmetry; exact Hmem |].
    split; [symmetry; exact Hin |].
    unfold trans_enabled.
    split.
    - rewrite Hsrc. exact Hprog.
    - rewrite <- Hmem, <- Hin. exact Hguard.
  Qed.

  Lemma ctx_at_satisfies_node_inv :
    forall u k,
      node_inv (cur_state (ctx_at u k)) (cur_mem (ctx_at u k)).
  Proof.
    intros u k.
    unfold ctx_at.
    destruct (cfg_at u k) as [s m] eqn:Hcfg.
    simpl.
    pose proof (node_inv_cfg_at u k) as Hinv.
    rewrite Hcfg in Hinv.
    exact Hinv.
  Qed.

  Lemma node_inv_obligation_valid :
    forall ps, ObligationValid (node_inv_obligation ps).
  Proof.
    intros ps u k.
    unfold node_inv_obligation.
    intro _Hmatch.
    apply ctx_at_satisfies_node_inv.
  Qed.

  Lemma generated_node_inv_obligation :
    forall ps,
      product_step_wf ps ->
      Generated (node_inv_obligation ps).
  Proof.
    intros ps Hwf.
    unfold Generated.
    exists NodeInvariant.
    exists (pst_trans ps).
    eapply GeneratedBy_product with (ps := ps).
    - exact Hwf.
    - reflexivity.
    - unfold gen_from_product_step.
      simpl.
      right.
      left.
      reflexivity.
  Qed.

  (* Couverture locale: de tout pas dangereux on extrait une obligation générée
     qui est fausse sur le contexte du pas dangereux. *)
  Theorem generation_coverage :
    forall u k, bad_local_step u k -> exists obl, Generated obl /\ ~ obl (ctx_at u k).
  Proof.
    intros u k Hbad.
    destruct Hbad as [ps [Hwf [Hreal _Hbadps]]].
    exists (prod_obligation ps).
    split.
    unfold Generated.
    exists (classify_product_step ps).
    exists (pst_trans ps).
    eapply GeneratedBy_product with (ps := ps).
    - exact Hwf.
    - reflexivity.
    - unfold gen_from_product_step.
      simpl.
      left.
      reflexivity.
    - unfold prod_obligation.
      intro Hobl.
      apply Hobl.
      apply ctx_at_matches_realized_ps; assumption.
  Qed.

  (* -------------------------------------------------------------------------- *)
  (* Théorème principal                                                          *)
  (* -------------------------------------------------------------------------- *)
  (* Sous avoids_bad_A et les hypothèses oracle, on obtient avoids_bad_G. *)
  Theorem oracle_conditional_correctness :
    forall u, avoids_bad_A u -> avoids_bad_G (run_trace u).
  Proof.
    intros u HA.
    destruct (classic (avoids_bad_G (run_trace u))) as [HG | HnG].
    - exact HG.
    - destruct (@bad_local_step_if_G_violated u HA HnG) as [k Hbad].
      destruct (@generation_coverage u k Hbad) as [obl [Hgen Hnot_at_k]].
      pose proof (@Oracle_complete obl Hgen) as Hor.
      pose proof (@Oracle_sound obl Hor) as Hvalid.
      exfalso.
      apply Hnot_at_k.
      apply Hvalid.
  Qed.

  Theorem oracle_conditional_correctness_with_node_inv :
    forall u,
      avoids_bad_A u ->
      (forall k, let '(s, m) := cfg_at u k in node_inv s m)
      /\ avoids_bad_G (run_trace u).
  Proof.
    intros u HA.
    split.
    - intro k.
      apply node_inv_cfg_at.
    - apply oracle_conditional_correctness.
      exact HA.
  Qed.

End Model.

End KairosOracleModel.
