(** Inject pre-oriented obligations from post-derived summaries. *)

val apply :
  post_generation:Post_generation.t ->
  Normalized_program.node ->
  Normalized_program.node
