(** Compact predicates for multi-clause helper contracts. *)

type t

val create :
  module_name:string ->
  imports:Why3.Ptree.decl list ->
  common_import:Why3.Ptree.decl ->
  env:Why_compile_expr.env ->
  inputs:Why3.Ptree.binder list ->
  formula_imports:
    (Kr_domain_core_syntax.history_free Kr_verification_ir.summary_formula list -> Why3.Ptree.decl list) ->
  compile_conditions:
    (Why_compile_expr.env ->
    Kr_verification.Kr_verification_obligations.conjunction ->
    Why3.Ptree.term list) ->
  Kr_verification.Kr_verification_proof_ir.shared_postcondition list ->
  t

val predicate_decl_and_call :
  inputs:Why3.Ptree.binder list ->
  used_inputs:Why_compile_expr.used_inputs ->
  name:string ->
  Why3.Ptree.term list ->
  Why3.Ptree.decl * Why3.Ptree.term

val shared_postcondition_call :
  t ->
  int ->
  Why3.Ptree.decl * Why3.Ptree.term * Why_compile_expr.used_inputs

val shared_post_modules :
  t -> (Why3.Ptree.ident * Why3.Ptree.decl list) list
