Require Import KairosOracle.
Require Import core.AutomataCorrectnessCore.
Require Import path.Step1SemanticProduct.
Require Import path.Step2GeneratedClauses.
Require Import path.Step3RelationalTriples.
Require Import path.Step4TransitionBundles.
Require Import path.Step5TripleValidity.
Require Import path.Step6ClauseRecovery.
Require Import path.Step7GlobalToLocal.

Set Implicit Arguments.

(* Minimal entry point for the current proved path.

   This file intentionally exposes only the mathematical kernel that is
   currently considered central:

   1. semantic product [program x A x G];
   2. generated semantic clauses;
   3. relational Hoare triples built from these clauses;
   4. later grouping by transition-level bundles;
   5. validity of generated triples;
   6. recovery of semantic clause validity on concrete ticks;
   7. global-to-local correctness reduction.

   External bridges toward Why3, validators, encodings, or checker answers are
   intentionally left out of this path. *)
Module Step1 := Step1SemanticProduct.
Module Step2 := Step2GeneratedClauses.
Module Step3 := Step3RelationalTriples.
Module Step4 := Step4TransitionBundles.
Module Step5 := Step5TripleValidity.
Module Step6 := Step6ClauseRecovery.
Module Step7 := Step7GlobalToLocal.

Definition bad_local_step_if_G_violated :=
  @KairosOracleModel.bad_local_step_if_G_violated.

Definition generation_coverage :=
  @KairosOracleModel.generation_coverage.

Definition triple_generation_coverage :=
  @KairosOracleModel.triple_generation_coverage.

Definition triple_valid_conditional_correctness :=
  @KairosOracleModel.triple_valid_conditional_correctness.

Definition triple_valid_conditional_correctness_under_wf :=
  @KairosOracleModel.triple_valid_conditional_correctness_under_wf.

Definition triple_valid_conditional_correctness_with_node_inv :=
  @KairosOracleModel.triple_valid_conditional_correctness_with_node_inv.

Definition triple_valid_conditional_correctness_with_node_inv_under_wf :=
  @KairosOracleModel.triple_valid_conditional_correctness_with_node_inv_under_wf.
