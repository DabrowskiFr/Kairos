(** Surface-level completion and expansion of observer transitions. *)

val expand_observers_in_transition :
  init_state:string -> Observers.schedule -> Kr_lang_surface.Kr_lang_surface_ast.transition -> Kr_lang_surface.Kr_lang_surface_ast.transition
(** Append the scheduled observer updates to one transition body. *)

val complete_observer_transitions : Kr_lang_surface.Kr_lang_surface_ast.node -> Kr_lang_surface.Kr_lang_surface_ast.transition list
(** Add explicit self-loop fallbacks for states lacking a catch-all transition. *)
