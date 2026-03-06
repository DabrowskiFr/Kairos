Require Import core.CoreStepSig.
Require Import core.CoreReactiveLaws.
Require Import monitor.MonitorSig.
Require Import monitor.InputMonitor.
Require Import monitor.GuaranteeMonitor.
Require Import monitor.ProductMonitor.
Require Import logic.FOLanguageSig.
Require Import logic.LTLPredicate.
Require Import logic.ShiftSpecSig.
Require Import contracts.ContractCompilerSig.
Require Import obligations.ObligationGenSig.
Require Import obligations.ObligationTaxonomySig.
Require Import obligations.ObligationStratifiedSig.
Require Import obligations.ObcAugmentationSig.
Require Import obligations.OracleSig.
Require Import obligations.OracleSemSig.
Require Import obligations.ImplementationValidatorBridge.
Require Import obligations.HoareExternalBridge.
Require Import obligations.TransitionTriplesBridge.
Require Import refinement.RefinementSig.
Require Import refinement.ShiftRefinement.
Require Import kernels.ShiftKernel.
Require Import kernels.SafetyKernel.
Require Import kernels.ObjectiveSafetyKernel.
Require Import kernels.SupportNonBlockingKernel.
Require Import integration.ThreeLayerArchitecture.
Require Import integration.AdmissibilityNonVacuity.
Require Import integration.ProgramLTLSpecBridge.

Set Implicit Arguments.

(* Canonical aliases to avoid divergence between blueprint and implementation. *)
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
Module Type ORACLE_SIG := OracleSig.ORACLE_SIG.
Module Type ORACLE_SEM_SIG := OracleSemSig.ORACLE_SEM_SIG.
Module Type IMPLEMENTATION_VALIDATOR_SIG := ImplementationValidatorBridge.IMPLEMENTATION_VALIDATOR_SIG.
Module Type HOARE_TASK_GEN_SIG := HoareExternalBridge.HOARE_TASK_GEN_SIG.
Module Type EXTERNAL_VC_TOOL_SIG := HoareExternalBridge.EXTERNAL_VC_TOOL_SIG.
Module Type TRANSITION_TRIPLE_GEN_SIG := TransitionTriplesBridge.TRANSITION_TRIPLE_GEN_SIG.
Module Type EXTERNAL_TRIPLE_ENCODING_SIG := TransitionTriplesBridge.EXTERNAL_TRIPLE_ENCODING_SIG.
Module Type EXTERNAL_ENCODED_CHECKER_SIG := TransitionTriplesBridge.EXTERNAL_ENCODED_CHECKER_SIG.
Module Type REFINEMENT_SIG := RefinementSig.REFINEMENT_SIG.
Module Type SHIFT_REFINEMENT_SIG := ShiftRefinement.SHIFT_REFINEMENT_SIG.
Module Type PROGRAM_LAYER_SIG := ThreeLayerArchitecture.PROGRAM_LAYER_SIG.
Module Type KAIROS_CORE_LAYER_SIG := ThreeLayerArchitecture.KAIROS_CORE_LAYER_SIG.
Module Type VALIDATION_LAYER_SIG := ThreeLayerArchitecture.VALIDATION_LAYER_SIG.
Module Type NON_VACUITY_SIG := AdmissibilityNonVacuity.NON_VACUITY_SIG.
Module Type PROGRAM_LTL_SPEC_SIG := ProgramLTLSpecBridge.PROGRAM_LTL_SPEC_SIG.

Module MakeShiftKernel := ShiftKernel.MakeShiftKernel.
Module MakeSafetyKernel := SafetyKernel.MakeSafetyKernel.
Module MakeObjectiveSafetyKernel := ObjectiveSafetyKernel.MakeObjectiveSafetyKernel.
Module MakeSupportNonBlockingKernel := SupportNonBlockingKernel.MakeSupportNonBlockingKernel.
Module MakeThreeLayerCorrectness := ThreeLayerArchitecture.MakeThreeLayerCorrectness.
Module MakeThreeLayerCorrectnessWithWitness := AdmissibilityNonVacuity.MakeThreeLayerCorrectnessWithWitness.
Module MakeProgramLTLCorrectness := ProgramLTLSpecBridge.MakeProgramLTLCorrectness.
Module MakeOracleSemFromValidator := ImplementationValidatorBridge.MakeOracleSemFromValidator.
Module MakeOracleSemFromHoareTool := HoareExternalBridge.MakeOracleSemFromHoareTool.
Module MakeOracleSemFromTransitionTriples := TransitionTriplesBridge.MakeOracleSemFromTransitionTriples.
