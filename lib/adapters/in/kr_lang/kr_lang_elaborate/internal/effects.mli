(** Inference of transitive method read/write effects. *)

module StringSet : Set.S with type elt = string

val infer_method_effects :
  StringSet.t ->
  Kr_lang_core.Kr_lang_core_ast.method_decl list ->
  Kr_lang_core.Kr_lang_core_ast.method_decl list
(** Annotate methods with the node variables they read and write. *)
