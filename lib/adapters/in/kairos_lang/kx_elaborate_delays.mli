(** Elaboration of executable one-instant historical reads used by observers.

    Delay cells are frontend-generated private ghosts.  Historical reads are
    removed before the core AST boundary. *)

type delay

val collect :
  Kx_elaborate_env.env ->
  Kx_surface_syntax.observer_decl list ->
  delay list

val ghosts : delay list -> Kx_surface_syntax.raw_vdecl list

val rewrite_observers :
  delay list ->
  Kx_surface_syntax.observer_decl list ->
  Kx_surface_syntax.observer_decl list

val append_commits :
  delay list ->
  Kx_surface_syntax.transition ->
  Kx_surface_syntax.transition

val state_invariants :
  states:string list ->
  init_state:string ->
  delay list ->
  (string * Kx_surface_syntax.hexpr) list
