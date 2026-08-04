(** Surface-level completion and expansion of observer transitions. *)

val expand_observers_in_transition :
  init_state:string -> Observers.schedule -> Surface.Ast.transition -> Surface.Ast.transition
(** Append the scheduled observer updates to one transition body. *)

val complete_observer_transitions : Surface.Ast.node -> Surface.Ast.transition list
(** Add explicit self-loop fallbacks for states lacking a catch-all transition. *)
