(** Eliminate [pre(x)] from executable observer statements.

    Each occurrence is replaced with a private generated variable storing the
    value of [x] from the preceding instant. *)

type delay

val collect :
  Env.env ->
  Surface.Ast.observer_decl list ->
  delay list

val ghosts : delay list -> Surface.Syntax.raw_vdecl list

val rewrite_observers :
  delay list ->
  Surface.Ast.observer_decl list ->
  Surface.Ast.observer_decl list

val append_commits :
  delay list ->
  Surface.Ast.transition ->
  Surface.Ast.transition

val state_invariants :
  states:string list ->
  init_state:string ->
  delay list ->
  (string * Surface.Syntax.hexpr) list
