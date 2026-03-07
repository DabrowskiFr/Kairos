Require Import KairosOracle.

Set Implicit Arguments.

(*
  Core proved facts extracted from [KairosOracleModel].
  These aliases make the proof nucleus explicit and reusable without
  re-axiomatizing local coverage.
*)
Module AutomataCorrectnessCore.
  Definition bad_local_step_if_G_violated :=
    @KairosOracleModel.bad_local_step_if_G_violated.

  Definition generation_coverage :=
    @KairosOracleModel.generation_coverage.

  Definition oracle_conditional_correctness :=
    @KairosOracleModel.oracle_conditional_correctness.
End AutomataCorrectnessCore.
