From Kairos Require Import KairosOracle.

Set Implicit Arguments.

Module Step1SemanticProduct.
  Definition WellFormedProgramModel := @KairosOracleModel.WellFormedProgramModel.
  Definition current_model_well_formed := @KairosOracleModel.current_model_well_formed.
  Definition ProductState := @KairosOracleModel.ProductState.
  Definition ProductStep := @KairosOracleModel.ProductStep.
  Definition product_step_wf := @KairosOracleModel.product_step_wf.
  Definition product_step_target := @KairosOracleModel.product_step_target.
  Definition product_step_is_bad_target := @KairosOracleModel.product_step_is_bad_target.
  Definition product_step_is_safe_target := @KairosOracleModel.product_step_is_safe_target.
  Definition run_product_state := @KairosOracleModel.run_product_state.
  Definition product_select_at := @KairosOracleModel.product_select_at.
  Definition product_select_at_wf := @KairosOracleModel.product_select_at_wf.
  Definition product_select_at_realizes := @KairosOracleModel.product_select_at_realizes.
  Definition product_progresses_at_each_tick := @KairosOracleModel.product_progresses_at_each_tick.
End Step1SemanticProduct.
