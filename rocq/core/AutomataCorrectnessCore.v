Require Import KairosOracle.

Set Implicit Arguments.

(*
  Core proved facts extracted from [KairosOracleModel].
  These aliases expose the main semantic stages of the current kernel without
  re-axiomatizing local coverage:

  1. a global violation of G yields a dangerous local step;
  2. a dangerous local step yields a falsified generated clause;
  3. valid generated triples imply conditional correctness.
*)
Module AutomataCorrectnessCore.
  Definition stage_global_violation_yields_dangerous_step :=
    @KairosOracleModel.bad_local_step_if_G_violated.

  Definition stage_dangerous_step_yields_falsified_clause :=
    @KairosOracleModel.generation_coverage.

  Definition stage_valid_triples_imply_conditional_correctness :=
    @KairosOracleModel.oracle_conditional_correctness.

  Definition bad_local_step_if_G_violated :=
    stage_global_violation_yields_dangerous_step.

  Definition generation_coverage :=
    stage_dangerous_step_yields_falsified_clause.

  Definition oracle_conditional_correctness :=
    stage_valid_triples_imply_conditional_correctness.
End AutomataCorrectnessCore.
