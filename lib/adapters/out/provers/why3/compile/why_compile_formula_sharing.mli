(** WhyML emission for formulas selected by the domain-level index.

    Formula equivalence and reuse analysis are owned by
    {!Contract_formula_index}; this module only emits declarations, imports,
    calls, and their WhyML parameters. *)

type t

val build :
  env:Why_compile_expr.env ->
  inputs:Why3.Ptree.binder list ->
  Contract_formula_index.t ->
  t

val definition_modules :
  t ->
  module_name:string ->
  imports:Why3.Ptree.decl list ->
  common_import:Why3.Ptree.decl ->
  (Why3.Ptree.ident * Why3.Ptree.decl list) list

val imports_for :
  t ->
  module_name:string ->
  Core_syntax.history_free Ir.summary_formula list ->
  Why3.Ptree.decl list

val compile :
  t ->
  env:Why_compile_expr.env ->
  Core_syntax.history_free Ir.summary_formula ->
  Why3.Ptree.term
