Require Import KairosOracle.

Set Implicit Arguments.

Module Step5TripleValidity.
  Definition init_node_inv_holds := @KairosOracleModel.init_node_inv_holds.
  Definition init_support_automaton_holds := @KairosOracleModel.init_support_automaton_holds.
  Definition node_inv_holds_on_run := @KairosOracleModel.node_inv_holds_on_run.
  Definition support_automaton_holds_on_run := @KairosOracleModel.support_automaton_holds_on_run.
End Step5TripleValidity.
