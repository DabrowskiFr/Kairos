type guard = Fo_formula.t
type transition = int * guard * int

type automaton = {
  atom_names : Ast.ident list;
  states_raw : Ast.ltl list;
  transitions_raw : transition list;
  states : Ast.ltl list;
  transitions : transition list;
  grouped : transition list;
}

type automata_atoms = {
  atom_map : (Ast.fo_atom * Ast.ident) list;
  atom_named_exprs : (Ast.ident * Ast.iexpr) list;
}

type automata_build = {
  atoms : automata_atoms;
  guarantee_atom_names : Ast.ident list;
  guarantee_spec : Ast.ltl;
  guarantee_automaton : automaton;
  assume_atoms : automata_atoms option;
  assume_atom_names : Ast.ident list;
  assume_spec : Ast.ltl option;
  assume_automaton : automaton option;
}

type node_builds = (Ast.ident * automata_build) list
