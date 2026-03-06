Require Import obligations.ObligationGenSig.

Set Implicit Arguments.

Inductive support_role : Type :=
| SupportAutomaton
| SupportUserInvariant.

Inductive obligation_role : Type :=
| ObjectiveNoBad
| CoherencyGoal
| Support (sr : support_role).

Module Type OBLIGATION_TAXONOMY_SIG (E : OBLIGATION_GEN_SIG).
  Parameter role_of : E.Obligation -> obligation_role.

  Definition GeneratedObjective (obl : E.Obligation) : Prop :=
    E.Generated obl /\ role_of obl = ObjectiveNoBad.

  Definition GeneratedSupportAutomaton (obl : E.Obligation) : Prop :=
    E.Generated obl /\ role_of obl = Support SupportAutomaton.

  Definition GeneratedCoherency (obl : E.Obligation) : Prop :=
    E.Generated obl /\ role_of obl = CoherencyGoal.

  Definition GeneratedSupportUserInvariant (obl : E.Obligation) : Prop :=
    E.Generated obl /\ role_of obl = Support SupportUserInvariant.

  Axiom generated_partition :
    forall obl,
      E.Generated obl ->
      GeneratedObjective obl \/
      GeneratedCoherency obl \/
      GeneratedSupportAutomaton obl \/
      GeneratedSupportUserInvariant obl.

  Axiom partition_disjoint_obj_coherency :
    forall obl,
      ~ (GeneratedObjective obl /\ GeneratedCoherency obl).

  Axiom partition_disjoint_coherency_auto :
    forall obl,
      ~ (GeneratedCoherency obl /\ GeneratedSupportAutomaton obl).

  Axiom partition_disjoint_coherency_user :
    forall obl,
      ~ (GeneratedCoherency obl /\ GeneratedSupportUserInvariant obl).

  Axiom partition_disjoint_obj_auto :
    forall obl,
      ~ (GeneratedObjective obl /\ GeneratedSupportAutomaton obl).

  Axiom partition_disjoint_obj_user :
    forall obl,
      ~ (GeneratedObjective obl /\ GeneratedSupportUserInvariant obl).

  Axiom partition_disjoint_auto_user :
    forall obl,
      ~ (GeneratedSupportAutomaton obl /\ GeneratedSupportUserInvariant obl).
End OBLIGATION_TAXONOMY_SIG.
