Require Import obligations.ObligationGenSig.
Require Import obligations.ObligationTaxonomySig.

Set Implicit Arguments.

Inductive obligation_phase : Type :=
| PhaseObjective
| PhaseCoherency
| PhaseSupportAutomaton
| PhaseSupportUserInvariant.

Definition phase_index (p : obligation_phase) : nat :=
  match p with
  | PhaseObjective => 0
  | PhaseCoherency => 1
  | PhaseSupportAutomaton => 2
  | PhaseSupportUserInvariant => 3
  end.

Module Type OBLIGATION_STRATIFIED_SIG
  (E : OBLIGATION_GEN_SIG)
  (T : OBLIGATION_TAXONOMY_SIG E).

  Parameter phase_of : E.Obligation -> obligation_phase.

  Axiom objective_phase :
    forall obl,
      T.GeneratedObjective obl ->
      phase_of obl = PhaseObjective.

  Axiom support_automaton_phase :
    forall obl,
      T.GeneratedSupportAutomaton obl ->
      phase_of obl = PhaseSupportAutomaton.

  Axiom coherency_phase :
    forall obl,
      T.GeneratedCoherency obl ->
      phase_of obl = PhaseCoherency.

  Axiom support_user_phase :
    forall obl,
      T.GeneratedSupportUserInvariant obl ->
      phase_of obl = PhaseSupportUserInvariant.

  Theorem objective_before_coherency :
    forall obl_obj obl_coh,
      T.GeneratedObjective obl_obj ->
      T.GeneratedCoherency obl_coh ->
      phase_index (phase_of obl_obj) < phase_index (phase_of obl_coh).
  Proof.
    intros obl_obj obl_coh Hobj Hcoh.
    rewrite (objective_phase (obl := obl_obj) Hobj).
    rewrite (coherency_phase (obl := obl_coh) Hcoh).
    simpl.
    auto.
  Qed.

  Theorem coherency_before_support_automaton :
    forall obl_coh obl_auto,
      T.GeneratedCoherency obl_coh ->
      T.GeneratedSupportAutomaton obl_auto ->
      phase_index (phase_of obl_coh) < phase_index (phase_of obl_auto).
  Proof.
    intros obl_coh obl_auto Hcoh Hauto.
    rewrite (coherency_phase (obl := obl_coh) Hcoh).
    rewrite (support_automaton_phase (obl := obl_auto) Hauto).
    simpl.
    auto.
  Qed.

  Theorem objective_before_support_automaton :
    forall obl_obj obl_auto,
      T.GeneratedObjective obl_obj ->
      T.GeneratedSupportAutomaton obl_auto ->
      phase_index (phase_of obl_obj) < phase_index (phase_of obl_auto).
  Proof.
    intros obl_obj obl_auto Hobj Hauto.
    rewrite (objective_phase (obl := obl_obj) Hobj).
    rewrite (support_automaton_phase (obl := obl_auto) Hauto).
    simpl.
    auto.
  Qed.

  Theorem support_automaton_before_support_user :
    forall obl_auto obl_user,
      T.GeneratedSupportAutomaton obl_auto ->
      T.GeneratedSupportUserInvariant obl_user ->
      phase_index (phase_of obl_auto) < phase_index (phase_of obl_user).
  Proof.
    intros obl_auto obl_user Hauto Huser.
    rewrite (support_automaton_phase (obl := obl_auto) Hauto).
    rewrite (support_user_phase (obl := obl_user) Huser).
    simpl.
    auto.
  Qed.
End OBLIGATION_STRATIFIED_SIG.
