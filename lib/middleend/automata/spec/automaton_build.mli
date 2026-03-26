val build :
  atom_map:(Ast.fo_atom * Ast.ident) list ->
  atom_names:Ast.ident list ->
  atom_named_exprs:(Ast.ident * Ast.iexpr) list ->
  Ast.ltl ->
  Automaton_types.automaton
