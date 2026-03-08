From Kairos.interfaces Require Import ExternalValidationAssumptions.

Set Implicit Arguments.

(* Preferred facade for validation-oriented naming.

   This file exists only to offer a readable entry point. The underlying
   implementation remains in [ExternalValidationAssumptions.v] for compatibility
   with the existing development. *)

Module Type VALIDATION_ASSUMPTIONS :=
  ExternalValidationAssumptions.VALIDATION_ASSUMPTIONS.

Module Type EXTERNAL_VALIDATION_ASSUMPTIONS :=
  ExternalValidationAssumptions.EXTERNAL_VALIDATION_ASSUMPTIONS.

Module MakeValidationAssumptionsFromOracleSem :=
  ExternalValidationAssumptions.MakeValidationAssumptionsFromOracleSem.

Module MakeValidationAssumptionsFromTransitionTriples :=
  ExternalValidationAssumptions.MakeValidationAssumptionsFromTransitionTriples.

Module MakeExternalValidationAssumptionsFromOracleSem :=
  ExternalValidationAssumptions.MakeExternalValidationAssumptionsFromOracleSem.

Module MakeExternalValidationAssumptionsFromTransitionTriples :=
  ExternalValidationAssumptions.MakeExternalValidationAssumptionsFromTransitionTriples.
