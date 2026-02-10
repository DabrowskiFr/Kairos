(** Interchangeable automaton engine interface.

    The engine builds a residual automaton from an LTL formula over atoms.
    Implementations should be swappable without changing the pipeline. *)

module type S = sig
  (** Residual state representation (LTL formula). *)
  type residual_state = Ast.fo_ltl
  (** Transition guard in DNF form. *)
  type guard = Automaton_types.guard
  (** Transition triple (src, guard, dst). *)
  type transition = int * guard * int

  (** Complete automaton build result. *)
  type automaton = {
    (** Ordered atom identifiers used by guards. *)
    atom_names: Ast.ident list;
    (** Raw states before minimization. *)
    states_raw: residual_state list;
    (** Raw transitions before minimization. *)
    transitions_raw: transition list;
    (** Minimized/stable states. *)
    states: residual_state list;
    (** Minimized/stable transitions. *)
    transitions: transition list;
    (** Grouped transitions (optional post‑processing). *)
    grouped: transition list;
  }

  (** Build a residual automaton for the given LTL spec and atom map. *)
  val build :
    atom_map:(Ast.fo * Ast.ident) list ->
    atom_names:Ast.ident list ->
    Ast.fo_ltl -> automaton
end

(** Default engine implementation. *)
module Engine : S

(** Re-export the default engine as a concrete module. *)
include S
  with type guard = Engine.guard
   and type transition = Engine.transition
   and type automaton = Engine.automaton
   and type residual_state = Engine.residual_state
