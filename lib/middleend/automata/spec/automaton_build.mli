(** Low-level bridge from a normalized Kairos LTL formula to the internal
    automaton representation.

    This module is responsible for invoking the external safety-automaton
    backend and normalizing its result into {!Automaton_types.automaton}. *)

val build :
  atom_map:(Ast.fo_atom * Ast.ident) list ->
  atom_names:Ast.ident list ->
  atom_named_exprs:(Ast.ident * Ast.iexpr) list ->
  Ast.ltl ->
  Automaton_types.automaton
(** [build ~atom_map ~atom_names ~atom_named_exprs spec] constructs the safety
    automaton for [spec], then normalizes states and guards into the automaton
    format consumed by the rest of the middleend. *)
