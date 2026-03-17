open Automaton_core

module type S = sig
  type residual_state = Ast.fo_ltl
  type guard = Automaton_types.guard
  type transition = int * guard * int

  type automaton = {
    atom_names : Ast.ident list;
    states_raw : residual_state list;
    transitions_raw : transition list;
    states : residual_state list;
    transitions : transition list;
    grouped : transition list;
  }

  val build :
    atom_map:(Ast.fo * Ast.ident) list -> atom_names:Ast.ident list -> Ast.fo_ltl -> automaton
end

module Engine : S = struct
  type residual_state = Ast.fo_ltl
  type guard = Automaton_types.guard
  type transition = int * guard * int

  type automaton = {
    atom_names : Ast.ident list;
    states_raw : residual_state list;
    transitions_raw : transition list;
    states : residual_state list;
    transitions : transition list;
    grouped : transition list;
  }

  let of_spot (a : Spot_automaton.automaton) : automaton =
    {
      atom_names = a.atom_names;
      states_raw = a.states_raw;
      transitions_raw = a.transitions_raw;
      states = a.states;
      transitions = a.transitions;
      grouped = a.grouped;
    }

  let build ~(atom_map : (Ast.fo * Ast.ident) list) ~(atom_names : Ast.ident list)
      (spec : Ast.fo_ltl) : automaton =
    of_spot (Spot_automaton.build ~atom_map ~atom_names spec)
end

include Engine
