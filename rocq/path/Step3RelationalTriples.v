From Kairos Require Import KairosOracle.

Set Implicit Arguments.

Module Step3RelationalTriples.
  Definition triple_target := @KairosOracleModel.triple_target.
  Definition RelHoareTriple := @KairosOracleModel.RelHoareTriple.
  Definition transition_realized_at := @KairosOracleModel.transition_realized_at.
  Definition transition_rel := @KairosOracleModel.transition_rel.
  Definition TripleValid := @KairosOracleModel.TripleValid.
  Definition init_node_inv_triple := @KairosOracleModel.init_node_inv_triple.
  Definition init_support_automaton_triple := @KairosOracleModel.init_support_automaton_triple.
  Definition node_inv_triple := @KairosOracleModel.node_inv_triple.
  Definition support_automaton_triple := @KairosOracleModel.support_automaton_triple.
  Definition no_bad_triple := @KairosOracleModel.no_bad_triple.
End Step3RelationalTriples.
