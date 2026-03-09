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
   - des clauses locales générées depuis des pas du produit,
   - des triples de Hoare relationnels construits depuis ces clauses.

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

  Record ProgramSemantics : Type := {
    prog_aut : ProgramAutomaton;
    prog_init_state : State;
    prog_default_init_mem : Mem;
    prog_init_mem_ok : Mem -> Prop;
  }.

  Variable Paut : ProgramAutomaton.
  Variable init_state : State.
  Variable init_mem : Mem.
  Variable init_mem_ok : Mem -> Prop.
  Hypothesis init_mem_ok_init : init_mem_ok init_mem.

  Definition program_part : ProgramSemantics :=
    {|
      prog_aut := Paut;
      prog_init_state := init_state;
      prog_default_init_mem := init_mem;
      prog_init_mem_ok := init_mem_ok;
    |}.

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

  (* Trace observable au tick k = entrée courante + sortie produite. *)
  Definition io_val : Type := InputVal * OutputVal.

  (* Configuration interne atteinte au début du tick k. *)
  Fixpoint cfg_at_from (m0 : Mem) (u : stream InputVal) (k : nat) : State * Mem :=
    match k with
    | O => (init_state, m0)
    | S n =>
        let '(s, m) := cfg_at_from m0 u n in
        let r := step s m (u n) in
        (st_next r, mem_next r)
    end.

  Definition cfg_at (u : stream InputVal) (k : nat) : State * Mem :=
    cfg_at_from init_mem u k.

  (* Pas exécuté au tick k. *)
  Definition step_at_from (m0 : Mem) (u : stream InputVal) (k : nat) : StepResult :=
    let '(s, m) := cfg_at_from m0 u k in
    step s m (u k).

  Definition step_at (u : stream InputVal) (k : nat) : StepResult :=
    step_at_from init_mem u k.

  (* Sortie observée au tick k. *)
  Definition out_at_from (m0 : Mem) (u : stream InputVal) (k : nat) : OutputVal :=
    out_cur (step_at_from m0 u k).

  Definition out_at (u : stream InputVal) (k : nat) : OutputVal :=
    out_at_from init_mem u k.

  (* Trace I/O complète produite par le programme. *)
  Definition run_trace_from (m0 : Mem) (u : stream InputVal) : stream io_val :=
    fun k => (u k, out_at_from m0 u k).

  Definition run_trace (u : stream InputVal) : stream io_val :=
    run_trace_from init_mem u.

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
    cur_assume_state : q A_aut;
    cur_guarantee_state : q G_aut;
    cur_mem : Mem;
    cur_input : InputVal;
    next_state : State;
    next_assume_state : q A_aut;
    next_guarantee_state : q G_aut;
    next_mem : Mem;
    cur_output : OutputVal;
  }.

  (* Contexte au tick k pour le flux u. *)
  Definition ctx_at_from (m0 : Mem) (u : stream InputVal) (k : nat) : StepCtx :=
    let '(s, m) := cfg_at_from m0 u k in
    let r := step s m (u k) in
    {|
      tick := k;
      cur_state := s;
      cur_assume_state := aut_state_at_A u k;
      cur_guarantee_state := aut_state_at_G (run_trace_from m0 u) k;
      cur_mem := m;
      cur_input := u k;
      next_state := st_next r;
      next_assume_state := aut_state_at_A u (S k);
      next_guarantee_state := aut_state_at_G (run_trace_from m0 u) (S k);
      next_mem := mem_next r;
      cur_output := out_cur r;
    |}.

  Definition ctx_at (u : stream InputVal) (k : nat) : StepCtx :=
    ctx_at_from init_mem u k.

  (* Une clause est un prédicat logique sur un contexte local.
     ClauseValid = vraie pour tous les ticks de toutes les exécutions. *)
  Definition Clause : Type := StepCtx -> Prop.
  Definition ClauseValid (cl : Clause) : Prop :=
    forall m0 u k, init_mem_ok m0 -> cl (ctx_at_from m0 u k).

  (* Automates d'hypothèse (entrées), de garantie (I/O) et invariants de nœud
     interprétés sur un contexte de tick dérivé de la trace d'exécution. *)
  Record NodeSpecification : Type := {
    spec_A_aut : SafetyAutomaton InputVal;
    spec_G_aut : SafetyAutomaton io_val;
    spec_node_inv : State -> StepCtx -> Prop;
  }.

  Variable node_inv : State -> StepCtx -> Prop.

  Definition specification_part : NodeSpecification :=
    {|
      spec_A_aut := A_aut;
      spec_G_aut := G_aut;
      spec_node_inv := node_inv;
    |}.

  (* -------------------------------------------------------------------------- *)
  (* Décalage abstrait des formules FO                                          *)
  (* -------------------------------------------------------------------------- *)
  (* Cette couche formalise abstraitement la transformation temporelle utilisée
     en implémentation (shift), sans exposer la syntaxe des opérateurs
     d'historique. *)
  Variable FO : Type.
  Variable eval_fo : StepCtx -> FO -> Prop.
  Variable shift_fo : nat -> FO -> FO.
  Variable node_inv_fo : State -> FO.
  Hypothesis node_inv_fo_correct :
    forall s ctx, eval_fo ctx (node_inv_fo s) <-> node_inv s ctx.

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
  | ObjectiveNoBad
  | InitialGoal
  | UserInvariant
  | AutomatonSupport.

  Definition generated_item : Type := origin * Clause.

  Definition init_product_state : ProductState :=
    {|
      ps_prog := init_state;
      ps_a := q0 A_aut;
      ps_g := q0 G_aut;
    |}.

  (* Le contexte concret "matche" un pas produit donné. *)
  Definition ctx_matches_ps (ctx : StepCtx) (ps : ProductStep) : Prop :=
    cur_state ctx = ps_prog (pst_from ps)
    /\ cur_mem ctx = pst_mem ps
    /\ cur_input ctx = pst_in ps
    /\ trans_enabled (pst_trans ps) (cur_state ctx) (cur_mem ctx) (cur_input ctx).

  Definition coherence_current (st : ProductState) (ctx : StepCtx) : Prop :=
    cur_state ctx = ps_prog st
    /\ cur_assume_state ctx = ps_a st
    /\ cur_guarantee_state ctx = ps_g st.

  Definition coherence_next (st : ProductState) (ctx : StepCtx) : Prop :=
    next_state ctx = ps_prog st
    /\ next_assume_state ctx = ps_a st
    /\ next_guarantee_state ctx = ps_g st.

  (* Clause canonique issue d'un pas produit:
     interdire que le contexte concret matche ce pas. *)
  Definition prod_obligation (ps : ProductStep) : Clause :=
    fun ctx =>
      node_inv (cur_state ctx) ctx ->
      coherence_current (pst_from ps) ctx ->
      ~ ctx_matches_ps ctx ps.

  (* Clause de cohérence d'invariant de nœud:
     dès qu'un contexte matche ps, l'invariant de nœud courant doit tenir. *)
  Definition node_inv_obligation (ps : ProductStep) : Clause :=
    fun ctx =>
      ctx_matches_ps ctx ps ->
      node_inv (cur_state ctx) ctx ->
      eval_fo ctx (shift_fo 1 (node_inv_fo (ps_prog (product_step_target ps)))).

  Definition support_automaton_obligation (ps : ProductStep) : Clause :=
    fun ctx =>
      ctx_matches_ps ctx ps ->
      coherence_current (pst_from ps) ctx ->
      coherence_next (product_step_target ps) ctx.

  Definition init_node_inv_obligation : Clause :=
    fun ctx => tick ctx = 0 -> node_inv init_state ctx.

  Definition init_support_automaton_obligation : Clause :=
    fun ctx => tick ctx = 0 -> coherence_current init_product_state ctx.

  Definition init_generated_items : list generated_item :=
    [ (InitialGoal, init_node_inv_obligation);
      (InitialGoal, init_support_automaton_obligation) ].

  (* Relation de génération (niveau preuve):
     l'obligation est générée depuis un pas produit bien formé. *)
  Inductive GeneratedBy : origin -> Clause -> Prop :=
  | GeneratedBy_init :
      forall o obl,
        In (o, obl) init_generated_items ->
        GeneratedBy o obl
  | GeneratedBy_node_inv :
      forall ps,
        product_step_wf ps ->
        GeneratedBy UserInvariant (node_inv_obligation ps)
  | GeneratedBy_support :
      forall ps,
        product_step_wf ps ->
        GeneratedBy AutomatonSupport (support_automaton_obligation ps)
  | GeneratedBy_no_bad :
      forall ps,
        product_step_wf ps ->
        product_step_is_bad_target ps ->
        GeneratedBy ObjectiveNoBad (prod_obligation ps)
  .

  (* Ensemble des obligations générées (oubliant origine/transition). *)
  Definition Generated (cl : Clause) : Prop :=
    exists o, GeneratedBy o cl.

  (* -------------------------------------------------------------------------- *)
  (* Triples de Hoare relationnels générés                                      *)
  (* -------------------------------------------------------------------------- *)
  Inductive triple_target : Type :=
  | TripleInit
  | TripleStep (t : Trans Paut).

  Record RelHoareTriple : Type := {
    ht_target : triple_target;
    ht_pre : Clause;
    ht_post : Clause;
    ht_origin : origin;
    ht_clause : Clause;
  }.

  Definition TrueClause : Clause := fun _ => True.
  Definition FalseClause : Clause := fun _ => False.

  Definition init_ctx (ctx : StepCtx) : Prop :=
    exists m0 u, init_mem_ok m0 /\ ctx = ctx_at_from m0 u 0.

  Definition transition_realized_at (m0 : Mem) (u : stream InputVal) (k : nat) (t : Trans Paut) : Prop :=
    let '(s, m) := cfg_at_from m0 u k in
    prog_select s m (u k) = t.

  Definition transition_rel (t : Trans Paut) (ctx ctx' : StepCtx) : Prop :=
    exists m0 u k,
      ctx = ctx_at_from m0 u k /\
      ctx' = ctx_at_from m0 u (S k) /\
      transition_realized_at m0 u k t.

  Definition TripleValid (ht : RelHoareTriple) : Prop :=
    match ht_target ht with
    | TripleInit =>
        forall ctx,
          init_ctx ctx ->
          ht_pre ht ctx ->
          ht_post ht ctx
    | TripleStep t =>
        forall ctx ctx',
          transition_rel t ctx ctx' ->
          ht_pre ht ctx ->
          ht_post ht ctx'
    end.

  Definition TripleValidOnAdmissibleRuns (ht : RelHoareTriple) : Prop :=
    match ht_target ht with
    | TripleInit =>
        forall m0 u,
          init_mem_ok m0 ->
          avoids_bad_A u ->
          ht_pre ht (ctx_at_from m0 u 0) ->
          ht_post ht (ctx_at_from m0 u 0)
    | TripleStep t =>
        forall m0 u k,
          init_mem_ok m0 ->
          avoids_bad_A u ->
          transition_realized_at m0 u k t ->
          ht_pre ht (ctx_at_from m0 u k) ->
          ht_post ht (ctx_at_from m0 u (S k))
    end.

  Definition init_node_inv_triple : RelHoareTriple :=
    {|
      ht_target := TripleInit;
      ht_pre := TrueClause;
      ht_post := fun ctx => node_inv init_state ctx;
      ht_origin := InitialGoal;
      ht_clause := init_node_inv_obligation;
    |}.

  Definition init_support_automaton_triple : RelHoareTriple :=
    {|
      ht_target := TripleInit;
      ht_pre := TrueClause;
      ht_post := fun ctx => coherence_current init_product_state ctx;
      ht_origin := InitialGoal;
      ht_clause := init_support_automaton_obligation;
    |}.

  Definition node_inv_pre (ps : ProductStep) : Clause :=
    fun ctx => ctx_matches_ps ctx ps /\ node_inv (cur_state ctx) ctx.

  Definition node_inv_post (ps : ProductStep) : Clause :=
    fun ctx => node_inv (ps_prog (product_step_target ps)) ctx.

  Definition node_inv_triple (ps : ProductStep) : RelHoareTriple :=
    {|
      ht_target := TripleStep (pst_trans ps);
      ht_pre := node_inv_pre ps;
      ht_post := node_inv_post ps;
      ht_origin := UserInvariant;
      ht_clause := node_inv_obligation ps;
    |}.

  Definition support_automaton_pre (ps : ProductStep) : Clause :=
    fun ctx => ctx_matches_ps ctx ps /\ coherence_current (pst_from ps) ctx.

  Definition support_automaton_post (ps : ProductStep) : Clause :=
    fun ctx => coherence_current (product_step_target ps) ctx.

  Definition support_automaton_triple (ps : ProductStep) : RelHoareTriple :=
    {|
      ht_target := TripleStep (pst_trans ps);
      ht_pre := support_automaton_pre ps;
      ht_post := support_automaton_post ps;
      ht_origin := AutomatonSupport;
      ht_clause := support_automaton_obligation ps;
    |}.

  Definition no_bad_pre (ps : ProductStep) : Clause :=
    fun ctx =>
      ctx_matches_ps ctx ps
      /\ node_inv (cur_state ctx) ctx
      /\ coherence_current (pst_from ps) ctx.

  Definition no_bad_triple (ps : ProductStep) : RelHoareTriple :=
    {|
      ht_target := TripleStep (pst_trans ps);
      ht_pre := no_bad_pre ps;
      ht_post := FalseClause;
      ht_origin := ObjectiveNoBad;
      ht_clause := prod_obligation ps;
    |}.

  Inductive GeneratedTripleBy : origin -> RelHoareTriple -> Prop :=
  | GeneratedTriple_init_node_inv :
      GeneratedTripleBy InitialGoal init_node_inv_triple
  | GeneratedTriple_init_support :
      GeneratedTripleBy InitialGoal init_support_automaton_triple
  | GeneratedTriple_node_inv :
      forall ps,
        product_step_wf ps ->
        GeneratedTripleBy UserInvariant (node_inv_triple ps)
  | GeneratedTriple_support :
      forall ps,
        product_step_wf ps ->
        GeneratedTripleBy AutomatonSupport (support_automaton_triple ps)
  | GeneratedTriple_no_bad :
      forall ps,
        product_step_wf ps ->
        product_step_is_bad_target ps ->
        GeneratedTripleBy ObjectiveNoBad (no_bad_triple ps).

  Definition GeneratedTriple (ht : RelHoareTriple) : Prop :=
    exists o, GeneratedTripleBy o ht.

  (* -------------------------------------------------------------------------- *)
  (* Exécution du produit le long d'un run programme                            *)
  (* -------------------------------------------------------------------------- *)
  Definition run_product_state_from (m0 : Mem) (u : stream InputVal) (k : nat) : ProductState :=
    let '(s, _m) := cfg_at_from m0 u k in
    {|
      ps_prog := s;
      ps_a := aut_state_at_A u k;
      ps_g := aut_state_at_G (run_trace_from m0 u) k;
    |}.

  Definition run_product_state (u : stream InputVal) (k : nat) : ProductState :=
    run_product_state_from init_mem u k.

  (* Invariants "jamais bad" si la propriété avoids_bad correspondante tient. *)
  Theorem no_bad_A_invariant :
    forall u, avoids_bad_A u -> forall k, ps_a (run_product_state u k) <> bad A_aut.
  Proof.
    intros u HA k.
    unfold run_product_state, run_product_state_from.
    destruct (cfg_at_from init_mem u k) as [s m].
    simpl.
    apply (HA k).
  Qed.

  Theorem no_bad_G_invariant :
    forall m0 u, avoids_bad_G (run_trace_from m0 u) -> forall k, ps_g (run_product_state_from m0 u k) <> bad G_aut.
  Proof.
    intros m0 u HG k.
    unfold run_product_state_from.
    destruct (cfg_at_from m0 u k) as [s m].
    simpl.
    apply (HG k).
  Qed.

  (* -------------------------------------------------------------------------- *)
  (* Validité des triples générés                                               *)
  (* -------------------------------------------------------------------------- *)
  Hypothesis GeneratedTripleValid :
    forall ht, GeneratedTriple ht -> TripleValid ht.

  (* Ce que signifie "le pas produit ps est celui effectivement réalisé au tick k". *)
  Definition product_step_realizes_at (m0 : Mem) (u : stream InputVal) (k : nat) (ps : ProductStep) : Prop :=
    let '(s, m) := cfg_at_from m0 u k in
    pst_from ps = run_product_state_from m0 u k
    /\ pst_mem ps = m
    /\ pst_in ps = u k
    /\ pst_trans ps = prog_select s m (u k).

  (* Conditions de base: états initiaux A/G non mauvais. *)
  Hypothesis A_init_not_bad : q0 A_aut <> bad A_aut.
  Hypothesis G_init_not_bad : q0 G_aut <> bad G_aut.

  Record WellFormedProgramModel : Prop := {
    wf_prog_select_enabled :
      forall s m i, trans_enabled (prog_select s m i) s m i;
    wf_select_A_src :
      forall qa i, src_e A_aut_e (select_A qa i) = qa;
    wf_select_G_src :
      forall qg io, src_e G_aut_e (select_G qg io) = qg;
    wf_select_A_label :
      forall qa i, label_e A_aut_e (select_A qa i) i;
    wf_select_G_label :
      forall qg io, label_e G_aut_e (select_G qg io) io;
    wf_A_init_not_bad :
      q0 A_aut <> bad A_aut;
    wf_G_init_not_bad :
      q0 G_aut <> bad G_aut;
  }.

  Proposition current_model_well_formed : WellFormedProgramModel.
  Proof.
    constructor.
    - exact prog_select_enabled.
    - exact select_A_src.
    - exact select_G_src.
    - exact select_A_label.
    - exact select_G_label.
    - exact A_init_not_bad.
    - exact G_init_not_bad.
  Qed.

  (* Pas local dangereux: il existe un pas produit réalisé, bien formé,
     dont la cible est bad_G et non bad_A. *)
  Definition bad_local_step (m0 : Mem) (u : stream InputVal) (k : nat) : Prop :=
    exists ps,
      product_step_wf ps
      /\ product_step_realizes_at m0 u k ps
      /\ product_step_is_bad_target ps.

  (* Sélecteur explicite du pas produit au tick k. *)
  Definition product_select_at (m0 : Mem) (u : stream InputVal) (k : nat) : ProductStep :=
    let '(s, m) := cfg_at_from m0 u k in
    let t := prog_select s m (u k) in
    let qa := aut_state_at_A u k in
    let qg := aut_state_at_G (run_trace_from m0 u) k in
    let ea := select_A qa (u k) in
    let obsg := product_obs_io t m (u k) in
    let eg := select_G qg obsg in
    {|
      pst_from := run_product_state_from m0 u k;
      pst_trans := t;
      pst_a_edge := ea;
      pst_g_edge := eg;
      pst_mem := m;
      pst_in := u k;
    |}.

  Lemma product_select_at_wf :
    forall m0 u k, product_step_wf (product_select_at m0 u k).
  Proof.
    intros m0 u k.
    unfold product_select_at.
    destruct (cfg_at_from m0 u k) as [s m] eqn:Hcfg.
    unfold product_step_wf.
    simpl.
    split.
    - unfold run_product_state_from.
      rewrite Hcfg.
      simpl.
      apply prog_select_enabled.
    - split.
      + unfold run_product_state_from.
        rewrite Hcfg.
        simpl.
        unfold edge_enabled.
        split.
        * apply select_A_src.
        * apply select_A_label.
      + split.
        * unfold run_product_state_from.
          rewrite Hcfg.
          simpl.
          unfold edge_enabled.
          split.
          -- apply select_G_src.
          -- apply select_G_label.
        * split.
          -- unfold run_product_state_from.
             rewrite Hcfg.
             simpl.
             reflexivity.
          -- unfold run_product_state_from.
             rewrite Hcfg.
             simpl.
             reflexivity.
  Qed.

  Lemma product_select_at_realizes :
    forall m0 u k, product_step_realizes_at m0 u k (product_select_at m0 u k).
  Proof.
    intros m0 u k.
    unfold product_step_realizes_at, product_select_at.
    destruct (cfg_at_from m0 u k) as [s m] eqn:Hcfg.
    unfold run_product_state_from.
    rewrite Hcfg.
    simpl.
    split; [reflexivity |].
    split; [reflexivity |].
    split; [reflexivity |].
    reflexivity.
  Qed.

  Lemma product_select_at_from :
    forall m0 u k, pst_from (product_select_at m0 u k) = run_product_state_from m0 u k.
  Proof.
    intros m0 u k.
    unfold product_select_at.
    destruct (cfg_at_from m0 u k) as [s m].
    reflexivity.
  Qed.

  (* Existence d'un pas produit réalisé à tout tick (construction explicite). *)
  Lemma realizable_product_step :
    forall m0 u k, exists ps, product_step_wf ps /\ product_step_realizes_at m0 u k ps.
  Proof.
    intros m0 u k.
    exists (product_select_at m0 u k).
    split.
    - apply product_select_at_wf.
    - apply product_select_at_realizes.
  Qed.

  (* Correction de projection cible:
     la cible du pas produit coïncide avec les états automates au tick suivant. *)
  Lemma realized_step_target_correct :
    forall m0 u k ps,
      product_step_wf ps ->
      product_step_realizes_at m0 u k ps ->
      ps_a (product_step_target ps) = aut_state_at_A u (S k)
      /\ ps_g (product_step_target ps) = aut_state_at_G (run_trace_from m0 u) (S k).
  Proof.
    intros m0 u k ps Hwf Hreal.
    unfold product_step_realizes_at in Hreal.
    destruct (cfg_at_from m0 u k) as [s m] eqn:Hcfg.
    destruct Hreal as [Hfrom [Hmem [Hin Htr]]].
    unfold product_step_wf in Hwf.
    destruct Hwf as [Hen [Hea [Heg [HdstA HdstG]]]].
    unfold product_step_target.
    split.
    - simpl.
      pose proof (f_equal ps_a Hfrom) as Ha_from.
      unfold run_product_state_from in Ha_from.
      rewrite Hcfg in Ha_from.
      simpl in Ha_from.
      rewrite HdstA.
      rewrite Ha_from.
      rewrite Hin.
      reflexivity.
    - simpl.
      pose proof (f_equal ps_g Hfrom) as Hg_from.
      unfold run_product_state_from in Hg_from.
      rewrite Hcfg in Hg_from.
      simpl in Hg_from.
      rewrite HdstG.
      rewrite Hg_from.
      rewrite Hin.
      unfold run_trace_from.
      unfold product_obs_io.
      rewrite Htr.
      rewrite Hmem.
      unfold out_at_from, step_at_from, step.
      rewrite Hcfg.
      reflexivity.
  Qed.

  (* Progression non bloquante explicite:
     à chaque tick, un pas produit bien formé est réalisable, et sa cible
     correspond exactement aux états des automates A/G au tick suivant. *)
  Theorem product_progresses_at_each_tick :
    forall m0 u k,
      exists ps,
        product_step_wf ps
        /\ product_step_realizes_at m0 u k ps
        /\ ps_a (product_step_target ps) = aut_state_at_A u (S k)
        /\ ps_g (product_step_target ps) = aut_state_at_G (run_trace_from m0 u) (S k).
  Proof.
    intros m0 u k.
    destruct (realizable_product_step m0 u k) as [ps [Hwf Hreal]].
    pose proof (@realized_step_target_correct m0 u k ps Hwf Hreal) as [Ha Hg].
    exists ps.
    split; [exact Hwf |].
    split; [exact Hreal |].
    split; assumption.
  Qed.

  (* Si G est violée globalement (sur run_trace), alors il existe un tick local dangereux. *)
  Theorem bad_local_step_if_G_violated :
    forall m0 u, avoids_bad_A u -> ~ avoids_bad_G (run_trace_from m0 u) -> exists k, bad_local_step m0 u k.
  Proof.
    intros m0 u HA HnG.
    unfold avoids_bad in HnG.
    apply not_all_ex_not in HnG.
    destruct HnG as [j Hj].
    assert (Hjbad : aut_state_at_G (run_trace_from m0 u) j = bad G_aut).
    { apply NNPP. exact Hj. }
    destruct j as [|k].
    - exfalso.
      simpl in Hjbad.
      exact (G_init_not_bad Hjbad).
    - destruct (realizable_product_step m0 u k) as [ps [Hwf Hreal]].
      exists k.
      unfold bad_local_step.
      exists ps.
      split; [exact Hwf |].
      split; [exact Hreal |].
      unfold product_step_is_bad_target.
      pose proof (@realized_step_target_correct m0 u k ps Hwf Hreal) as [Ha Hg].
      split.
      + rewrite Ha.
        apply HA.
      + rewrite Hg.
        exact Hjbad.
  Qed.

  (* Un pas produit réalisé se reflète bien dans le contexte concret ctx_at. *)
  Proposition ctx_at_matches_realized_ps :
    forall m0 u k ps,
      product_step_wf ps ->
      product_step_realizes_at m0 u k ps ->
      ctx_matches_ps (ctx_at_from m0 u k) ps.
  Proof.
    intros m0 u k ps Hwf Hreal.
    unfold product_step_realizes_at in Hreal.
    destruct (cfg_at_from m0 u k) as [s m] eqn:Hcfg.
    destruct Hreal as [Hfrom [Hmem [Hin _Htr]]].
    pose proof (f_equal ps_prog Hfrom) as Hprog.
    unfold run_product_state_from in Hprog.
    rewrite Hcfg in Hprog.
    simpl in Hprog.
    unfold ctx_matches_ps, ctx_at_from.
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

  Local Lemma realized_step_prog_target_correct :
    forall m0 u k ps,
      product_step_realizes_at m0 u k ps ->
      ps_prog (product_step_target ps) = cur_state (ctx_at_from m0 u (S k)).
  Proof.
    intros m0 u k ps Hreal.
    unfold product_step_realizes_at in Hreal.
    destruct (cfg_at_from m0 u k) as [s m] eqn:Hcfg.
    destruct Hreal as [_Hfrom [_Hmem [_Hin Htr]]].
    unfold product_step_target.
    simpl.
    rewrite Htr.
    unfold ctx_at_from.
    simpl.
    rewrite Hcfg.
    unfold step.
    reflexivity.
  Qed.

  Local Lemma matched_step_prog_target_correct :
    forall m0 u k ps,
      transition_realized_at m0 u k (pst_trans ps) ->
      ctx_matches_ps (ctx_at_from m0 u k) ps ->
      ps_prog (product_step_target ps) = cur_state (ctx_at_from m0 u (S k)).
  Proof.
    intros m0 u k ps Htr Hmatch.
    unfold transition_realized_at in Htr.
    destruct (cfg_at_from m0 u k) as [s m] eqn:Hcfg.
    simpl in Htr.
    destruct Hmatch as [_Hstate [_Hmem [_Hin _Hen]]].
    unfold product_step_target.
    simpl.
    rewrite <- Htr.
    unfold ctx_at_from.
    simpl.
    rewrite Hcfg.
    unfold step.
    reflexivity.
  Qed.

  Local Fact run_product_state_0 :
    forall m0 u, run_product_state_from m0 u 0 = init_product_state.
  Proof.
    intros m0 u.
    unfold run_product_state_from, init_product_state.
    simpl.
    reflexivity.
  Qed.

  Local Fact init_ctx_at_0 :
    forall m0 u, init_mem_ok m0 -> init_ctx (ctx_at_from m0 u 0).
  Proof.
    intros m0 u Hm0.
    unfold init_ctx.
    exists m0, u.
    split; [exact Hm0 |].
    reflexivity.
  Qed.

  Proposition transition_rel_of_realized_step :
    forall m0 u k ps,
      product_step_realizes_at m0 u k ps ->
      transition_rel (pst_trans ps) (ctx_at_from m0 u k) (ctx_at_from m0 u (S k)).
  Proof.
    intros m0 u k ps Hreal.
    exists m0, u, k.
    split; [reflexivity |].
    split; [reflexivity |].
    unfold transition_realized_at.
    unfold product_step_realizes_at in Hreal.
    destruct (cfg_at_from m0 u k) as [s m].
    destruct Hreal as [_ [_ [_ Htr]]].
    symmetry.
    exact Htr.
  Qed.

  Local Lemma realized_step_target_matches_run_product_successor :
    forall m0 u k ps,
      product_step_wf ps ->
      product_step_realizes_at m0 u k ps ->
      product_step_target ps = run_product_state_from m0 u (S k).
  Proof.
    intros m0 u k ps Hwf Hreal.
    destruct (@realized_step_target_correct m0 u k ps Hwf Hreal) as [Ha Hg].
    pose proof (@realized_step_prog_target_correct m0 u k ps Hreal) as Hp.
    destruct (product_step_target ps) as [sp sa sg].
    unfold run_product_state_from.
    destruct (cfg_at_from m0 u (S k)) as [s m] eqn:Hcfg.
    simpl in *.
    assert (Hcur : cur_state (ctx_at_from m0 u (S k)) = s).
    { unfold ctx_at_from. simpl. rewrite Hcfg. reflexivity. }
    rewrite Hcur in Hp.
    subst sp sa sg.
    reflexivity.
  Qed.

  Local Lemma bad_local_step_implies_not_avoids_bad_G :
    forall m0 u k,
      bad_local_step m0 u k ->
      ~ avoids_bad_G (run_trace_from m0 u).
  Proof.
    intros m0 u k [ps [Hwf [Hreal Hbad]]].
    intro HG.
    destruct (@realized_step_target_correct m0 u k ps Hwf Hreal) as [_ Hg].
    unfold product_step_is_bad_target in Hbad.
    destruct Hbad as [_ Hgbad].
    specialize (HG (S k)).
    rewrite <- Hg in HG.
    exact (HG Hgbad).
  Qed.

  Local Lemma generated_init_node_inv_obligation :
    Generated init_node_inv_obligation.
  Proof.
    unfold Generated.
    exists InitialGoal.
    apply GeneratedBy_init.
    unfold init_generated_items.
    simpl.
      left.
      reflexivity.
  Qed.

  Local Lemma generated_init_support_automaton_obligation :
    Generated init_support_automaton_obligation.
  Proof.
    unfold Generated.
    exists InitialGoal.
    apply GeneratedBy_init.
    unfold init_generated_items.
    simpl.
    right.
    left.
    reflexivity.
  Qed.

  Local Lemma generated_node_inv_obligation :
    forall ps,
      product_step_wf ps ->
      Generated (node_inv_obligation ps).
  Proof.
    intros ps Hwf.
    unfold Generated.
    exists UserInvariant.
    apply GeneratedBy_node_inv.
    exact Hwf.
  Qed.

  Local Lemma generated_support_automaton_obligation :
    forall ps,
      product_step_wf ps ->
      Generated (support_automaton_obligation ps).
  Proof.
    intros ps Hwf.
    unfold Generated.
    exists AutomatonSupport.
    apply GeneratedBy_support.
    exact Hwf.
  Qed.

  Local Lemma generated_init_node_inv_triple :
    GeneratedTriple init_node_inv_triple.
  Proof.
    unfold GeneratedTriple.
    exists InitialGoal.
    constructor.
  Qed.

  Local Lemma generated_init_support_automaton_triple :
    GeneratedTriple init_support_automaton_triple.
  Proof.
    unfold GeneratedTriple.
    exists InitialGoal.
    constructor.
  Qed.

  Local Lemma generated_node_inv_triple :
    forall ps,
      product_step_wf ps ->
      GeneratedTriple (node_inv_triple ps).
  Proof.
    intros ps Hwf.
    unfold GeneratedTriple.
    exists UserInvariant.
    constructor; exact Hwf.
  Qed.

  Local Lemma generated_support_automaton_triple :
    forall ps,
      product_step_wf ps ->
      GeneratedTriple (support_automaton_triple ps).
  Proof.
    intros ps Hwf.
    unfold GeneratedTriple.
    exists AutomatonSupport.
    constructor; exact Hwf.
  Qed.

  Local Lemma generated_no_bad_triple :
    forall ps,
      product_step_wf ps ->
      product_step_is_bad_target ps ->
      GeneratedTriple (no_bad_triple ps).
  Proof.
    intros ps Hwf Hbad.
    unfold GeneratedTriple.
    exists ObjectiveNoBad.
    constructor; assumption.
  Qed.

  (* ---------------------------------------------------------------------- *)
  (* Stage 3: helper facts hold along admissible runs                        *)
  (* ---------------------------------------------------------------------- *)

  Proposition init_node_inv_holds :
    forall m0 u, init_mem_ok m0 -> node_inv (cur_state (ctx_at_from m0 u 0)) (ctx_at_from m0 u 0).
  Proof.
    intros m0 u Hm0.
    pose proof generated_init_node_inv_triple as Hgen.
    pose proof (GeneratedTripleValid (ht := init_node_inv_triple) Hgen) as Hvalid.
    unfold TripleValid in Hvalid.
    specialize (Hvalid (ctx_at_from m0 u 0)).
    unfold init_node_inv_triple, TrueClause in Hvalid.
    simpl in Hvalid.
    apply Hvalid.
    - apply init_ctx_at_0; exact Hm0.
    - trivial.
  Qed.

  Proposition init_support_automaton_holds :
    forall m0 u, init_mem_ok m0 -> coherence_current init_product_state (ctx_at_from m0 u 0).
  Proof.
    intros m0 u _Hm0.
    unfold coherence_current, init_product_state, ctx_at_from, cfg_at_from.
    simpl.
    repeat split; reflexivity.
  Qed.

  Proposition support_automaton_holds_on_run :
    forall m0 u k,
      init_mem_ok m0 ->
      avoids_bad_A u ->
      coherence_current (run_product_state_from m0 u k) (ctx_at_from m0 u k).
  Proof.
    intros m0 u k _Hm0 _HA.
    unfold coherence_current, run_product_state_from, ctx_at_from.
    destruct (cfg_at_from m0 u k) as [s m].
    simpl.
    repeat split; reflexivity.
  Qed.

  Proposition node_inv_holds_on_run :
    forall m0 u k,
      init_mem_ok m0 ->
      avoids_bad_A u ->
      node_inv (cur_state (ctx_at_from m0 u k)) (ctx_at_from m0 u k).
  Proof.
    intros m0 u k Hm0 HA.
    induction k as [|k IH].
    - apply init_node_inv_holds; exact Hm0.
    - pose proof (product_select_at_wf m0 u k) as Hwf.
      pose proof (product_select_at_realizes m0 u k) as Hreal.
      pose proof (@ctx_at_matches_realized_ps m0 u k (product_select_at m0 u k) Hwf Hreal) as Hmatch.
      pose proof (@generated_node_inv_triple (product_select_at m0 u k) Hwf) as Hgen.
      pose proof (GeneratedTripleValid (ht := node_inv_triple (product_select_at m0 u k)) Hgen) as Hvalid.
      pose proof (@transition_rel_of_realized_step m0 u k (product_select_at m0 u k) Hreal) as Hrel.
      unfold TripleValid in Hvalid.
      simpl in Hvalid.
      pose proof (Hvalid (ctx_at_from m0 u k) (ctx_at_from m0 u (S k)) Hrel (conj Hmatch IH)) as Hnext.
      pose proof (@realized_step_prog_target_correct m0 u k (product_select_at m0 u k) Hreal) as Hprog.
      rewrite <- Hprog.
      exact Hnext.
  Qed.

  Local Proposition coherence_context_holds_on_run :
    forall m0 u k ps,
      init_mem_ok m0 ->
      avoids_bad_A u ->
      product_step_realizes_at m0 u k ps ->
      node_inv (cur_state (ctx_at_from m0 u k)) (ctx_at_from m0 u k)
      /\ coherence_current (pst_from ps) (ctx_at_from m0 u k).
  Proof.
    intros m0 u k ps Hm0 HA Hreal.
    split.
    - apply node_inv_holds_on_run.
      exact Hm0.
      exact HA.
    - pose proof (@support_automaton_holds_on_run m0 u k Hm0 HA) as Hsup.
      unfold product_step_realizes_at in Hreal.
      destruct (cfg_at_from m0 u k) as [s m] eqn:Hcfg.
      destruct Hreal as [Hfrom [_ [_ _]]].
      rewrite Hfrom.
      exact Hsup.
  Qed.

  Local Proposition helper_context_holds_on_run :
    forall m0 u k ps,
      init_mem_ok m0 ->
      avoids_bad_A u ->
      product_step_realizes_at m0 u k ps ->
      node_inv (cur_state (ctx_at_from m0 u k)) (ctx_at_from m0 u k)
      /\ coherence_current (pst_from ps) (ctx_at_from m0 u k).
  Proof.
    exact coherence_context_holds_on_run.
  Qed.

  Local Lemma coherence_current_exact_on_run :
    forall m0 u k st,
      coherence_current st (ctx_at_from m0 u k) ->
      st = run_product_state_from m0 u k.
  Proof.
    intros m0 u k [sp qa qg] Hcoh.
    unfold coherence_current, ctx_at_from, run_product_state_from in Hcoh |- *.
    destruct (cfg_at_from m0 u k) as [s m].
    simpl in Hcoh |- *.
    destruct Hcoh as [Hs [Ha Hg]].
    subst.
    reflexivity.
  Qed.

  (* ---------------------------------------------------------------------- *)
  (* Stage 4: a dangerous realized step falsifies a generated clause         *)
  (* ---------------------------------------------------------------------- *)

  (* Couverture locale: de tout pas dangereux on extrait une clause générée
     qui est fausse sur le contexte du pas dangereux. *)
  Theorem generation_coverage :
    forall m0 u k,
      init_mem_ok m0 ->
      avoids_bad_A u ->
      bad_local_step m0 u k ->
      exists obl, Generated obl /\ ~ obl (ctx_at_from m0 u k).
  Proof.
    intros m0 u k Hm0 HA Hbad.
    destruct Hbad as [ps [Hwf [Hreal Hbadps]]].
    exists (prod_obligation ps).
    split.
    unfold Generated.
    exists ObjectiveNoBad.
    eapply GeneratedBy_no_bad.
    - exact Hwf.
    - exact Hbadps.
    - unfold prod_obligation.
      intro Hobl.
      pose proof (@ctx_at_matches_realized_ps m0 u k ps Hwf Hreal) as Hmatch.
    pose proof (@coherence_context_holds_on_run m0 u k ps Hm0 HA Hreal) as [Hinv Hsup].
      apply (Hobl Hinv Hsup Hmatch).
  Qed.

  (* ---------------------------------------------------------------------- *)
  (* Stage 5: the same dangerous tick activates a generated NoBad triple     *)
  (* ---------------------------------------------------------------------- *)

  Theorem triple_generation_coverage :
    forall m0 u k,
      init_mem_ok m0 ->
      avoids_bad_A u ->
      bad_local_step m0 u k ->
      exists ht,
        GeneratedTriple ht
        /\ exists ps,
             product_step_wf ps
             /\ product_step_realizes_at m0 u k ps
             /\ ht = no_bad_triple ps
        /\ ht_pre ht (ctx_at_from m0 u k).
  Proof.
    intros m0 u k Hm0 HA Hbad.
    destruct Hbad as [ps [Hwf [Hreal Hbadps]]].
    exists (no_bad_triple ps).
    split.
    - apply generated_no_bad_triple.
      exact Hwf.
      exact Hbadps.
    - exists ps.
      split; [exact Hwf |].
      split; [exact Hreal |].
      split; [reflexivity |].
      unfold no_bad_pre.
      split.
      + apply ctx_at_matches_realized_ps.
        * exact Hwf.
        * exact Hreal.
      + apply helper_context_holds_on_run.
        * exact Hm0.
        * exact HA.
        * exact Hreal.
  Qed.

  Local Lemma generated_no_bad_triple_contradiction :
    forall m0 u k ps,
      GeneratedTriple (no_bad_triple ps) ->
      product_step_realizes_at m0 u k ps ->
      ht_pre (no_bad_triple ps) (ctx_at_from m0 u k) ->
      False.
  Proof.
    intros m0 u k ps Hgen Hreal Hepre.
    pose proof (GeneratedTripleValid (ht := no_bad_triple ps) Hgen) as Hvalid.
    pose proof (@transition_rel_of_realized_step m0 u k ps Hreal) as Hrel.
    unfold TripleValid in Hvalid.
    unfold no_bad_triple, FalseClause in Hvalid.
    simpl in Hvalid.
    exact (Hvalid (ctx_at_from m0 u k) (ctx_at_from m0 u (S k)) Hrel Hepre).
  Qed.

  (* ---------------------------------------------------------------------- *)
  (* Stage 6: valid generated triples imply conditional correctness          *)
  (* ---------------------------------------------------------------------- *)
  (* Sous avoids_bad_A et la validité des triples générés, on obtient
     avoids_bad_G. *)
  Theorem triple_valid_conditional_correctness :
    forall m0 u, init_mem_ok m0 -> avoids_bad_A u -> avoids_bad_G (run_trace_from m0 u).
  Proof.
    intros m0 u Hm0 HA.
    destruct (classic (avoids_bad_G (run_trace_from m0 u))) as [HG | HnG].
    - exact HG.
    - destruct (@bad_local_step_if_G_violated m0 u HA HnG) as [k Hbad].
      destruct (@triple_generation_coverage m0 u k Hm0 HA Hbad)
        as [_ht [Hgen [ps [_Hwf [Hreal [Heq Hepre]]]]]].
      rewrite Heq in Hgen, Hepre.
      exfalso.
      eapply generated_no_bad_triple_contradiction.
      + exact Hgen.
      + exact Hreal.
      + exact Hepre.
  Qed.

  Theorem triple_valid_conditional_correctness_under_wf :
    WellFormedProgramModel ->
    forall m0 u, init_mem_ok m0 -> avoids_bad_A u -> avoids_bad_G (run_trace_from m0 u).
  Proof.
    intros _wf m0 u Hm0 HA.
    apply triple_valid_conditional_correctness.
    exact Hm0.
    exact HA.
  Qed.

  Theorem triple_valid_conditional_correctness_with_node_inv :
    forall m0 u,
      init_mem_ok m0 ->
      avoids_bad_A u ->
      (forall k, node_inv (cur_state (ctx_at_from m0 u k)) (ctx_at_from m0 u k))
      /\ avoids_bad_G (run_trace_from m0 u).
  Proof.
    intros m0 u Hm0 HA.
    split.
    - intro k.
      apply node_inv_holds_on_run.
      exact Hm0.
      exact HA.
    - apply triple_valid_conditional_correctness.
      exact Hm0.
      exact HA.
  Qed.

  Theorem triple_valid_conditional_correctness_with_node_inv_under_wf :
    WellFormedProgramModel ->
    forall m0 u,
      init_mem_ok m0 ->
      avoids_bad_A u ->
      (forall k, node_inv (cur_state (ctx_at_from m0 u k)) (ctx_at_from m0 u k))
      /\ avoids_bad_G (run_trace_from m0 u).
  Proof.
    intros _wf m0 u Hm0 HA.
    apply triple_valid_conditional_correctness_with_node_inv.
    exact Hm0.
    exact HA.
  Qed.

  (* ---------------------------------------------------------------------- *)
  (* Exposed theorems hiding the initial-memory witness                     *)
  (* ---------------------------------------------------------------------- *)
  Definition avoids_bad_G_from_admissible_init (u : stream InputVal) : Prop :=
    forall m0, init_mem_ok m0 -> avoids_bad_G (run_trace_from m0 u).

  Definition node_inv_holds_from_admissible_init (u : stream InputVal) : Prop :=
    forall m0, init_mem_ok m0 ->
      forall k, node_inv (cur_state (ctx_at_from m0 u k)) (ctx_at_from m0 u k).

  Definition globally_correct : Prop :=
    forall m0 u, init_mem_ok m0 -> avoids_bad_A u -> avoids_bad_G (run_trace_from m0 u).

  Definition node_invariants_true_on_admissible_runs : Prop :=
    forall m0 u k,
      init_mem_ok m0 ->
      avoids_bad_A u ->
      node_inv (cur_state (ctx_at_from m0 u k)) (ctx_at_from m0 u k).

  Theorem validation_conditional_correctness :
    WellFormedProgramModel ->
    forall u, avoids_bad_A u -> avoids_bad_G_from_admissible_init u.
  Proof.
    intros Hwf u HA m0 Hm0.
    apply triple_valid_conditional_correctness_under_wf.
    - exact Hwf.
    - exact Hm0.
    - exact HA.
  Qed.

  Theorem validation_conditional_correctness_with_node_inv :
    WellFormedProgramModel ->
    forall u,
      avoids_bad_A u ->
      node_inv_holds_from_admissible_init u
      /\ avoids_bad_G_from_admissible_init u.
  Proof.
    intros Hwf u HA.
    split.
    - intros m0 Hm0 k.
      pose proof (triple_valid_conditional_correctness_with_node_inv_under_wf
                    Hwf (m0 := m0) (u := u) Hm0 HA)
        as [Hinv _].
      exact (Hinv k).
    - intros m0 Hm0.
      pose proof (triple_valid_conditional_correctness_with_node_inv_under_wf
                    Hwf (m0 := m0) (u := u) Hm0 HA)
        as [_ HG].
      exact HG.
  Qed.

  Theorem relative_completeness_no_bad :
    WellFormedProgramModel ->
    globally_correct ->
    forall ps,
      product_step_wf ps ->
      product_step_is_bad_target ps ->
      TripleValidOnAdmissibleRuns (no_bad_triple ps).
  Proof.
    intros _wf Hglob ps Hwf Hbadtgt.
    unfold TripleValidOnAdmissibleRuns, no_bad_triple, FalseClause.
    simpl.
    intros m0 u k Hm0 HA Htr Hpre.
    destruct Hpre as [Hmatch [_Hinv Hsup]].
    assert (Hfrom : pst_from ps = run_product_state_from m0 u k).
    { eapply coherence_current_exact_on_run; exact Hsup. }
    assert (Hreal : product_step_realizes_at m0 u k ps).
    { unfold product_step_realizes_at.
      destruct (cfg_at_from m0 u k) as [s m] eqn:Hcfg.
      destruct Hmatch as [_Hstate [Hmem [Hin _Hen]]].
      unfold ctx_at_from in Hmem, Hin.
      simpl in Hmem, Hin.
      rewrite Hcfg in Hmem, Hin.
      split; [exact Hfrom |].
      split; [symmetry; exact Hmem |].
      split; [symmetry; exact Hin |].
      unfold transition_realized_at in Htr.
      rewrite Hcfg in Htr.
      symmetry; exact Htr. }
    assert (Hbad : bad_local_step m0 u k).
    { exists ps. split; [exact Hwf |]. split; [exact Hreal | exact Hbadtgt]. }
    exfalso.
    apply (@bad_local_step_implies_not_avoids_bad_G m0 u k Hbad).
    apply Hglob; assumption.
  Qed.

  Theorem relative_completeness_automaton_support :
    WellFormedProgramModel ->
    TripleValidOnAdmissibleRuns init_support_automaton_triple
    /\
    forall ps,
      product_step_wf ps ->
      TripleValidOnAdmissibleRuns (support_automaton_triple ps).
  Proof.
    intros _wf.
    split.
    - unfold TripleValidOnAdmissibleRuns, init_support_automaton_triple, TrueClause.
      simpl.
      intros m0 u Hm0 _HA _.
      apply init_support_automaton_holds; assumption.
    - intros ps Hwf.
      unfold TripleValidOnAdmissibleRuns, support_automaton_triple.
      unfold support_automaton_post.
      simpl.
      intros m0 u k Hm0 HA Htr Hpre.
      destruct Hpre as [Hmatch Hsup].
      assert (Hfrom : pst_from ps = run_product_state_from m0 u k).
      { eapply coherence_current_exact_on_run; exact Hsup. }
      assert (Hreal : product_step_realizes_at m0 u k ps).
      { unfold product_step_realizes_at.
        destruct (cfg_at_from m0 u k) as [s m] eqn:Hcfg.
        destruct Hmatch as [_Hstate [Hmem [Hin _Hen]]].
        unfold ctx_at_from in Hmem, Hin.
        simpl in Hmem, Hin.
        rewrite Hcfg in Hmem, Hin.
        split; [exact Hfrom |].
        split; [symmetry; exact Hmem |].
        split; [symmetry; exact Hin |].
        unfold transition_realized_at in Htr.
        rewrite Hcfg in Htr.
        symmetry; exact Htr. }
      change (coherence_current (product_step_target ps) (ctx_at_from m0 u (S k))).
      unfold coherence_current.
      pose proof (@realized_step_prog_target_correct m0 u k ps Hreal) as Hprog.
      pose proof (@realized_step_target_correct m0 u k ps Hwf Hreal) as [Ha Hg].
      split.
      + symmetry; exact Hprog.
      + split.
        * replace (cur_assume_state (ctx_at_from m0 u (S k))) with (aut_state_at_A u (S k)).
          symmetry; exact Ha.
          unfold ctx_at_from.
          destruct (cfg_at_from m0 u (S k)) as [s' m']; reflexivity.
        * replace (cur_guarantee_state (ctx_at_from m0 u (S k))) with (aut_state_at_G (run_trace_from m0 u) (S k)).
          symmetry; exact Hg.
          unfold ctx_at_from.
          destruct (cfg_at_from m0 u (S k)) as [s' m']; reflexivity.
    Qed.

  Theorem relative_completeness_user_invariant :
    WellFormedProgramModel ->
    node_invariants_true_on_admissible_runs ->
    TripleValidOnAdmissibleRuns init_node_inv_triple
    /\
    forall ps,
      product_step_wf ps ->
      TripleValidOnAdmissibleRuns (node_inv_triple ps).
  Proof.
    intros _wf Htrue.
    split.
    - unfold TripleValidOnAdmissibleRuns, init_node_inv_triple, TrueClause.
      simpl.
      intros m0 u Hm0 HA _.
      change (node_inv init_state (ctx_at_from m0 u 0)).
      exact (Htrue m0 u 0 Hm0 HA).
    - intros ps Hwf.
      unfold TripleValidOnAdmissibleRuns, node_inv_triple.
      unfold node_inv_post.
      simpl.
      intros m0 u k Hm0 HA Htr Hpre.
      change (node_inv (ps_prog (product_step_target ps)) (ctx_at_from m0 u (S k))).
      destruct Hpre as [Hmatch _Hinv].
      pose proof (@matched_step_prog_target_correct m0 u k ps Htr Hmatch) as Hp.
      rewrite Hp.
      exact (Htrue m0 u (S k) Hm0 HA).
  Qed.

  Theorem relative_completeness_generated_triples :
    WellFormedProgramModel ->
    globally_correct ->
    node_invariants_true_on_admissible_runs ->
    forall ht,
      GeneratedTriple ht ->
      TripleValidOnAdmissibleRuns ht.
  Proof.
    intros Hwf Hglob Htrue ht Hgen.
    destruct Hgen as [o Hgen].
    inversion Hgen; subst; clear Hgen.
    - destruct (relative_completeness_user_invariant Hwf Htrue) as [Hinit _].
      exact Hinit.
    - destruct (relative_completeness_automaton_support Hwf) as [Hinit _].
      exact Hinit.
    - destruct (relative_completeness_user_invariant Hwf Htrue) as [_ Hprop].
      apply Hprop; assumption.
    - destruct (relative_completeness_automaton_support Hwf) as [_ Hprop].
      apply Hprop; assumption.
    - eapply relative_completeness_no_bad; eauto.
  Qed.

  Theorem triple_valid_conditional_correctness_default :
    forall u, avoids_bad_A u -> avoids_bad_G (run_trace u).
  Proof.
    intros u HA.
    eapply triple_valid_conditional_correctness.
    - exact init_mem_ok_init.
    - exact HA.
  Qed.

  Theorem oracle_conditional_correctness :
    forall u, avoids_bad_A u -> avoids_bad_G (run_trace u).
  Proof.
    exact triple_valid_conditional_correctness_default.
  Qed.

  Theorem triple_valid_conditional_correctness_with_node_inv_default :
    forall u,
      avoids_bad_A u ->
      (forall k, node_inv (cur_state (ctx_at u k)) (ctx_at u k))
      /\ avoids_bad_G (run_trace u).
  Proof.
    intros u HA.
    eapply triple_valid_conditional_correctness_with_node_inv.
    - exact init_mem_ok_init.
    - exact HA.
  Qed.

  Theorem oracle_conditional_correctness_with_node_inv :
    forall u,
      avoids_bad_A u ->
      (forall k, node_inv (cur_state (ctx_at u k)) (ctx_at u k))
      /\ avoids_bad_G (run_trace u).
  Proof.
    exact triple_valid_conditional_correctness_with_node_inv_default.
  Qed.

End Model.

End KairosOracleModel.
