(** Compact predicates for multi-clause helper contracts. *)

type t

val create :
  module_name:string ->
  imports:Why3.Ptree.decl list ->
  common_import:Why3.Ptree.decl ->
  inputs:Why3.Ptree.binder list ->
  formula_imports:
    (Core_syntax.history_free Ir.summary_formula list -> Why3.Ptree.decl list) ->
  t

val predicate_decl_and_call :
  inputs:Why3.Ptree.binder list ->
  used_inputs:Why_compile_expr.used_inputs ->
  name:string ->
  Why3.Ptree.term list ->
  Why3.Ptree.decl * Why3.Ptree.term

val shared_post_call :
  t ->
  used_inputs:Why_compile_expr.used_inputs ->
  formulas:Core_syntax.history_free Ir.summary_formula list ->
  Why3.Ptree.term list ->
  Why3.Ptree.decl * Why3.Ptree.term

val shared_post_modules :
  t -> (Why3.Ptree.ident * Why3.Ptree.decl list) list
