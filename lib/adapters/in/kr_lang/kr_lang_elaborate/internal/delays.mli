(** Eliminate [pre(x)] from executable observer statements.

    Each occurrence is replaced with a private generated variable storing the
    value of [x] from the preceding instant. *)

type delay

val collect :
  Env.env ->
  Kr_lang_surface.Kr_lang_surface_ast.observer_decl list ->
  delay list

val ghosts : delay list -> Kr_lang_surface.Kr_lang_surface_syntax.raw_vdecl list

val rewrite_observers :
  delay list ->
  Kr_lang_surface.Kr_lang_surface_ast.observer_decl list ->
  Kr_lang_surface.Kr_lang_surface_ast.observer_decl list

val append_commits :
  delay list ->
  Kr_lang_surface.Kr_lang_surface_ast.transition ->
  Kr_lang_surface.Kr_lang_surface_ast.transition

val state_invariants :
  states:string list ->
  init_state:string ->
  delay list ->
  (string * Kr_lang_surface.Kr_lang_surface_syntax.hexpr) list
