(** Direct WhyML contracts for individual and grouped product steps. *)

val compile_conditions :
  Why_compile_formula_sharing.t ->
  Why_compile_expr.env ->
  Kairos_verification_obligations.Verification_obligations.conjunction ->
  Why3.Ptree.term list

type individual_contract = {
  decls : Why3.Ptree.decl list;
  spec : Why3.Ptree.spec;
  used_inputs : Why_compile_expr.used_inputs;
}

type grouped_contract = {
  decls : Why3.Ptree.decl list;
  spec : Why3.Ptree.spec;
  post_call : pre_snapshot_name:string -> Why3.Ptree.term;
  used_inputs : Why_compile_expr.used_inputs;
}

val individual_helper_contract :
  env:Why_compile_expr.env ->
  inputs:Why3.Ptree.binder list ->
  formula_sharing:Why_compile_formula_sharing.t ->
  formula_imports:(Core_syntax.history_free Ir.summary_formula list -> Why3.Ptree.decl list) ->
  helper_name:string ->
  bundles:Why_compile_bundles.t ->
  Kairos_verification_obligations.Verification_proof_ir.individual ->
  individual_contract

val grouped_helper_contract :
  env:Why_compile_expr.env ->
  inputs:Why3.Ptree.binder list ->
  formula_sharing:Why_compile_formula_sharing.t ->
  formula_imports:
    (Core_syntax.history_free Ir.summary_formula list -> Why3.Ptree.decl list) ->
  post_pred_name:string ->
  Kairos_verification_obligations.Verification_proof_ir.grouped ->
  grouped_contract
