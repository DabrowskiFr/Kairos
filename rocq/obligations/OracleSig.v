Require Import obligations.ObligationGenSig.

Set Implicit Arguments.

(* Historical filename kept for compatibility.

   Preferred reading/API:
   - module type [VALIDATION_SIG]

   Legacy compatibility alias:
   - module type [ORACLE_SIG] *)

Module Type ORACLE_SIG (E : OBLIGATION_GEN_SIG).
  Parameter Oracle : E.Clause -> bool.
  Parameter ClauseValid : E.Clause -> Prop.

  Axiom Oracle_sound :
    forall cl, Oracle cl = true -> ClauseValid cl.

  Axiom Oracle_complete :
    forall cl, E.Generated cl -> Oracle cl = true.
End ORACLE_SIG.

Module Type VALIDATION_SIG (E : OBLIGATION_GEN_SIG).
  Include ORACLE_SIG E.
End VALIDATION_SIG.
