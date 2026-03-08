From Kairos Require Import KairosOracle.

Set Implicit Arguments.

Module Step7GlobalToLocal.
  Definition bad_local_step_if_G_violated := @KairosOracleModel.bad_local_step_if_G_violated.
  Definition triple_valid_conditional_correctness := @KairosOracleModel.triple_valid_conditional_correctness.
  Definition triple_valid_conditional_correctness_with_node_inv :=
    @KairosOracleModel.triple_valid_conditional_correctness_with_node_inv.
End Step7GlobalToLocal.
