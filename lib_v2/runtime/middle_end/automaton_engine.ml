open Automaton_core
open Automaton_residual
open Automaton_bdd

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

module Legacy_engine : S = struct
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

  let build ~(atom_map : (Ast.fo * Ast.ident) list) ~(atom_names : Ast.ident list)
      (spec : Ast.fo_ltl) : automaton =
    let states_raw, transitions_raw_bdd = build_residual_graph_bdd ~atom_map ~atom_names spec in
    let states, transitions_bdd = minimize_residual_graph_bdd states_raw transitions_raw_bdd in
    let to_guard (i, guard, j) = (i, bdd_to_guard atom_names guard, j) in
    let transitions_raw = List.map to_guard transitions_raw_bdd in
    let transitions = List.map to_guard transitions_bdd in
    { atom_names; states_raw; transitions_raw; states; transitions; grouped = transitions }
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

  let of_legacy (a : Legacy_engine.automaton) : automaton =
    {
      atom_names = a.atom_names;
      states_raw = a.states_raw;
      transitions_raw = a.transitions_raw;
      states = a.states;
      transitions = a.transitions;
      grouped = a.grouped;
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
    match Sys.getenv_opt "KAIROS_AUTOMATON_BACKEND" with
    | Some "legacy" -> of_legacy (Legacy_engine.build ~atom_map ~atom_names spec)
    | _ -> of_spot (Spot_automaton.build ~atom_map ~atom_names spec)
end

include Engine
