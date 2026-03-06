Require Import obligations.ObligationGenSig.

Set Implicit Arguments.

Module Type ORACLE_SIG (E : OBLIGATION_GEN_SIG).
  Parameter Oracle : E.Obligation -> bool.
  Parameter ObligationValid : E.Obligation -> Prop.

  Axiom Oracle_sound :
    forall obl, Oracle obl = true -> ObligationValid obl.

  Axiom Oracle_complete :
    forall obl, E.Generated obl -> Oracle obl = true.
End ORACLE_SIG.
