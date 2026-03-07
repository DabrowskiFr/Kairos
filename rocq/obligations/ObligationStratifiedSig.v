Require Import obligations.ObligationGenSig.
Require Import obligations.ObligationTaxonomySig.

Set Implicit Arguments.

Inductive obligation_phase : Type :=
| PhaseHelperInit
| PhaseHelperPropagation
| PhaseSafety.

Definition phase_index (p : obligation_phase) : nat :=
  match p with
  | PhaseHelperInit => 0
  | PhaseHelperPropagation => 1
  | PhaseSafety => 2
  end.

Module Type OBLIGATION_STRATIFIED_SIG
  (E : OBLIGATION_GEN_SIG)
  (T : OBLIGATION_TAXONOMY_SIG E).

  Definition GeneratedPropagationUserInvariant (cl : E.Clause) : Prop :=
    E.Generated cl /\ T.role_of cl = HelperClause Propagation HelperUserInvariant.

  Definition GeneratedPropagationAutomatonSupport (cl : E.Clause) : Prop :=
    E.Generated cl /\ T.role_of cl = HelperClause Propagation HelperAutomatonSupport.

  Parameter phase_of : E.Clause -> obligation_phase.

  Axiom helper_init_phase :
    forall cl,
      T.GeneratedInitialGoal cl ->
      phase_of cl = PhaseHelperInit.

  Axiom helper_propagation_user_phase :
    forall cl,
      GeneratedPropagationUserInvariant cl ->
      phase_of cl = PhaseHelperPropagation.

  Axiom helper_propagation_automaton_phase :
    forall cl,
      GeneratedPropagationAutomatonSupport cl ->
      phase_of cl = PhaseHelperPropagation.

  Axiom safety_phase :
    forall cl,
      T.GeneratedSafety cl ->
      phase_of cl = PhaseSafety.

  Theorem helper_init_before_helper_propagation_user :
    forall cl_init cl_user,
      T.GeneratedInitialGoal cl_init ->
      GeneratedPropagationUserInvariant cl_user ->
      phase_index (phase_of cl_init) < phase_index (phase_of cl_user).
  Proof.
    intros cl_init cl_user Hinit Huser.
    rewrite (helper_init_phase (cl := cl_init) Hinit).
    rewrite (helper_propagation_user_phase (cl := cl_user) Huser).
    simpl.
    auto.
  Qed.

  Theorem helper_init_before_helper_propagation_automaton :
    forall cl_init cl_auto,
      T.GeneratedInitialGoal cl_init ->
      GeneratedPropagationAutomatonSupport cl_auto ->
      phase_index (phase_of cl_init) < phase_index (phase_of cl_auto).
  Proof.
    intros cl_init cl_auto Hinit Hauto.
    rewrite (helper_init_phase (cl := cl_init) Hinit).
    rewrite (helper_propagation_automaton_phase (cl := cl_auto) Hauto).
    simpl.
    auto.
  Qed.

  Theorem helper_propagation_before_safety_from_user :
    forall cl_user cl_obj,
      GeneratedPropagationUserInvariant cl_user ->
      T.GeneratedSafety cl_obj ->
      phase_index (phase_of cl_user) < phase_index (phase_of cl_obj).
  Proof.
    intros cl_user cl_obj Huser Hobj.
    rewrite (helper_propagation_user_phase (cl := cl_user) Huser).
    rewrite (safety_phase (cl := cl_obj) Hobj).
    simpl.
    auto.
  Qed.

  Theorem helper_propagation_before_safety_from_automaton :
    forall cl_auto cl_obj,
      GeneratedPropagationAutomatonSupport cl_auto ->
      T.GeneratedSafety cl_obj ->
      phase_index (phase_of cl_auto) < phase_index (phase_of cl_obj).
  Proof.
    intros cl_auto cl_obj Hauto Hobj.
    rewrite (helper_propagation_automaton_phase (cl := cl_auto) Hauto).
    rewrite (safety_phase (cl := cl_obj) Hobj).
    simpl.
    auto.
  Qed.
End OBLIGATION_STRATIFIED_SIG.
