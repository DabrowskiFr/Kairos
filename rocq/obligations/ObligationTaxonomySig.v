From Kairos.obligations Require Import ObligationGenSig.

Set Implicit Arguments.

Inductive major_role : Type :=
| Safety
| Helper.

Inductive helper_phase : Type :=
| InitGoal
| Propagation.

Inductive helper_kind : Type :=
| HelperUserInvariant
| HelperAutomatonSupport.

Inductive obligation_role : Type :=
| SafetyNoBad
| HelperClause (ph : helper_phase) (k : helper_kind).

Module Type OBLIGATION_TAXONOMY_SIG (E : OBLIGATION_GEN_SIG).
  Parameter role_of : E.Clause -> obligation_role.

  Definition major_role_of (cl : E.Clause) : major_role :=
    match role_of cl with
    | SafetyNoBad => Safety
    | HelperClause _ _ => Helper
    end.

  Definition GeneratedSafety (cl : E.Clause) : Prop :=
    E.Generated cl /\ role_of cl = SafetyNoBad.

  Definition GeneratedHelper (cl : E.Clause) : Prop :=
    E.Generated cl /\ exists ph k, role_of cl = HelperClause ph k.

  Definition GeneratedHelperInit (cl : E.Clause) : Prop :=
    E.Generated cl
    /\ exists k, role_of cl = HelperClause InitGoal k.

  Definition GeneratedHelperPropagation (cl : E.Clause) : Prop :=
    E.Generated cl
    /\ exists k, role_of cl = HelperClause Propagation k.

  Definition GeneratedHelperUserInvariant (cl : E.Clause) : Prop :=
    E.Generated cl
    /\ exists ph, role_of cl = HelperClause ph HelperUserInvariant.

  Definition GeneratedHelperAutomatonSupport (cl : E.Clause) : Prop :=
    E.Generated cl
    /\ exists ph, role_of cl = HelperClause ph HelperAutomatonSupport.

  Definition GeneratedInitUserInvariant (cl : E.Clause) : Prop :=
    E.Generated cl /\ role_of cl = HelperClause InitGoal HelperUserInvariant.

  Definition GeneratedInitAutomatonSupport (cl : E.Clause) : Prop :=
    E.Generated cl /\ role_of cl = HelperClause InitGoal HelperAutomatonSupport.

  Definition GeneratedPropagationUserInvariant (cl : E.Clause) : Prop :=
    E.Generated cl /\ role_of cl = HelperClause Propagation HelperUserInvariant.

  Definition GeneratedPropagationAutomatonSupport (cl : E.Clause) : Prop :=
    E.Generated cl /\ role_of cl = HelperClause Propagation HelperAutomatonSupport.

  (* Backward-compatible aliases for older kernel names. *)
  Definition GeneratedObjective := GeneratedSafety.
  Definition GeneratedInitialGoal := GeneratedHelperInit.
  Definition GeneratedUserInvariant := GeneratedHelperUserInvariant.
  Definition GeneratedSupportAutomaton := GeneratedHelperAutomatonSupport.

  Axiom generated_partition :
    forall cl,
      E.Generated cl ->
      GeneratedSafety cl \/
      GeneratedInitUserInvariant cl \/
      GeneratedInitAutomatonSupport cl \/
      GeneratedPropagationUserInvariant cl \/
      GeneratedPropagationAutomatonSupport cl.

  Axiom partition_disjoint_safety_helper :
    forall cl,
      ~ (GeneratedSafety cl /\ GeneratedHelper cl).

  Axiom partition_disjoint_init_prop_user :
    forall cl,
      ~ (GeneratedInitUserInvariant cl /\ GeneratedPropagationUserInvariant cl).

  Axiom partition_disjoint_init_prop_auto :
    forall cl,
      ~ (GeneratedInitAutomatonSupport cl /\ GeneratedPropagationAutomatonSupport cl).

  Axiom partition_disjoint_user_auto_in_init :
    forall cl,
      ~ (GeneratedInitUserInvariant cl /\ GeneratedInitAutomatonSupport cl).

  Axiom partition_disjoint_user_auto_in_propagation :
    forall cl,
      ~ (GeneratedPropagationUserInvariant cl /\ GeneratedPropagationAutomatonSupport cl).
End OBLIGATION_TAXONOMY_SIG.
