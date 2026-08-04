(** Inference of transitive method read/write effects. *)

module StringSet : Set.S with type elt = string

val infer_method_effects :
  StringSet.t ->
  Core.Ast.method_decl list ->
  Core.Ast.method_decl list
(** Annotate methods with the node variables they read and write. *)
