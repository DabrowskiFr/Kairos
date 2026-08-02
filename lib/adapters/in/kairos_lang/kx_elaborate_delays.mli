(** Eliminate [pre(x)] from executable observer statements.

    Each occurrence is replaced with a private generated variable storing the
    value of [x] from the preceding instant. *)

type delay

val collect :
  Kx_elaborate_env.env ->
  Kx_surface_ast.observer_decl list ->
  delay list

val ghosts : delay list -> Kx_surface_syntax.raw_vdecl list

val rewrite_observers :
  delay list ->
  Kx_surface_ast.observer_decl list ->
  Kx_surface_ast.observer_decl list

val append_commits :
  delay list ->
  Kx_surface_ast.transition ->
  Kx_surface_ast.transition

val state_invariants :
  states:string list ->
  init_state:string ->
  delay list ->
  (string * Kx_surface_syntax.hexpr) list
