Require Import KairosOracle.
Require Import MainProofPath.
Require Import core.CoreStepSig.
Require Import core.CoreReactiveLaws.
Require Import core.AutomataCorrectnessCore.
Require Import logic.FOLanguageSig.
Require Import logic.LTLPredicate.
Require Import logic.ShiftSpecSig.
Require Import monitor.MonitorSig.
Require Import monitor.InputMonitor.
Require Import monitor.GuaranteeMonitor.
Require Import monitor.ProductMonitor.
Require Import contracts.ContractCompilerSig.
Require Import obligations.ObligationGenSig.
Require Import obligations.ObligationTaxonomySig.
Require Import obligations.ObligationStratifiedSig.
Require Import obligations.ObcAugmentationSig.
Require Import obligations.OracleSig.
Require Import obligations.OracleSemSig.
Require Import refinement.RefinementSig.
Require Import refinement.ShiftRefinement.
Require Import kernels.ShiftKernel.
Require Import kernels.SafetyKernel.
Require Import kernels.ObjectiveSafetyKernel.
Require Import kernels.SupportNonBlockingKernel.
Require Import integration.ThreeLayerFromCore.

Set Implicit Arguments.

(* This file is now intentionally narrow.

   It documents the current mathematical path that should remain readable:

   - [KairosOracle] for the main semantics and theorem;
   - [MainProofPath] for the minimal entry point;
   - lightweight aliases for the core logical signatures reused across the
     development.

   Files that model external validation stacks or checker bridges are no longer
   imported here. They are considered optional refinements and should not be
   mistaken for part of the main proof path. *)

Module Type CORE_STEP_SIG := CoreStepSig.CORE_STEP_SIG.
Module Type CORE_REACTIVE_LAWS_SIG := CoreReactiveLaws.CORE_REACTIVE_LAWS_SIG.
Module Type MONITOR_SIG := MonitorSig.MONITOR_SIG.
Module Type INPUT_ADMISSIBILITY_SIG := InputMonitor.INPUT_ADMISSIBILITY_SIG.
Module Type GUARANTEE_MONITOR_SIG := GuaranteeMonitor.GUARANTEE_MONITOR_SIG.
Module Type PRODUCT_MONITOR_SIG := ProductMonitor.PRODUCT_MONITOR_SIG.
Module Type FO_LOGIC_SIG := FOLanguageSig.FO_LOGIC_SIG.
Module Type LTL_PREDICATE_SIG := LTLPredicate.LTL_PREDICATE_SIG.
Module Type SHIFT_SPEC_SIG := ShiftSpecSig.SHIFT_SPEC_SIG.
Module Type CONTRACT_COMPILER_SIG := ContractCompilerSig.CONTRACT_COMPILER_SIG.
Module Type OBLIGATION_GEN_SIG := ObligationGenSig.OBLIGATION_GEN_SIG.
Module Type OBLIGATION_TAXONOMY_SIG := ObligationTaxonomySig.OBLIGATION_TAXONOMY_SIG.
Module Type OBLIGATION_STRATIFIED_SIG := ObligationStratifiedSig.OBLIGATION_STRATIFIED_SIG.
Module Type OBC_AUGMENTATION_SIG := ObcAugmentationSig.OBC_AUGMENTATION_SIG.
Module Type VALIDATION_SIG := OracleSig.VALIDATION_SIG.
Module Type VALIDATION_SEM_SIG := OracleSemSig.VALIDATION_SEM_SIG.
Module Type REFINEMENT_SIG := RefinementSig.REFINEMENT_SIG.
Module Type SHIFT_REFINEMENT_SIG := ShiftRefinement.SHIFT_REFINEMENT_SIG.
Module Type KAIROS_CORE_FROM_PROVED_SIG := ThreeLayerFromCore.KAIROS_CORE_FROM_PROVED_SIG.

Module MakeShiftKernel := ShiftKernel.MakeShiftKernel.
Module MakeSafetyKernel := SafetyKernel.MakeSafetyKernel.
Module MakeObjectiveSafetyKernel := ObjectiveSafetyKernel.MakeObjectiveSafetyKernel.
Module MakeSupportNonBlockingKernel := SupportNonBlockingKernel.MakeSupportNonBlockingKernel.
Module MakeCoverageFromProvedCore := ThreeLayerFromCore.MakeCoverageFromProvedCore.

(* Optional refinement files intentionally excluded from this blueprint:
   - interfaces/ExternalValidationAssumptions.v
   - integration/ThreeLayerArchitecture.v
   - integration/AutomataFinalCorrectness.v
   - obligations/TransitionTriplesBridge.v
   - obligations/HoareExternalBridge.v
   - obligations/ImplementationValidatorBridge.v *)
