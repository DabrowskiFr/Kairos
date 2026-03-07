Set Implicit Arguments.

Module Type OBLIGATION_GEN_SIG.
  Parameter StepCtx : Type.
  Definition Clause : Type := StepCtx -> Prop.

  Parameter Origin : Type.
  Parameter GeneratedBy : Origin -> Clause -> Prop.

  Definition Generated (cl : Clause) : Prop :=
    exists o, GeneratedBy o cl.
End OBLIGATION_GEN_SIG.
