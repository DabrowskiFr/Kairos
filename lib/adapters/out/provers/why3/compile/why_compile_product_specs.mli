(** Direct WhyML contracts for individual and grouped product steps. *)

val step_pre_terms_with_rec :
  Why_compile_formula_sharing.t ->
  Why_compile_expr.env ->
  string ->
  Step_contract_projection.step_contract ->
  Why3.Ptree.term list

val step_post_terms_with_rec :
  Why_compile_formula_sharing.t ->
  Why_compile_expr.env ->
  string ->
  Step_contract_projection.step_contract ->
  Why3.Ptree.term list

type individual_contract = {
  decls : Why3.Ptree.decl list;
  spec : Why3.Ptree.spec;
  used_inputs : Why_compile_expr.used_inputs;
}

type grouped_contract = {
  post_pred_decl : Why3.Ptree.decl;
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
  shared_post_call:
    (used_inputs:Why_compile_expr.used_inputs ->
    formulas:Core_syntax.history_free Ir.summary_formula list ->
    Why3.Ptree.term list ->
    Why3.Ptree.decl * Why3.Ptree.term) ->
  Step_contract_projection.step_contract ->
  individual_contract

val grouped_helper_contract :
  env:Why_compile_expr.env ->
  inputs:Why3.Ptree.binder list ->
  post_pred_name:string ->
  Why_compile_product_group_terms.t ->
  grouped_contract
