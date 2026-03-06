Set Implicit Arguments.

Module Type OBLIGATION_GEN_SIG.
  Parameter StepCtx : Type.
  Definition Obligation : Type := StepCtx -> Prop.

  Parameter Origin : Type.
  Parameter GeneratedBy : Origin -> Obligation -> Prop.

  Definition Generated (obl : Obligation) : Prop :=
    exists o, GeneratedBy o obl.
End OBLIGATION_GEN_SIG.
