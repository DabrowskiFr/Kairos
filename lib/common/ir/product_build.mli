(** Product exploration and analysis between program states and
    assume/guarantee automata. *)

type analysis = {
  exploration : Product_types.exploration;
  assume_bad_idx : int;
  guarantee_bad_idx : int;
  guarantee_state_labels : string list;
  assume_state_labels : string list;
  guarantee_grouped_edges : Spot_automaton.transition list;
  assume_grouped_edges : Spot_automaton.transition list;
  guarantee_atom_map_exprs : (Ast.ident * Ast.iexpr) list;
  assume_atom_map_exprs : (Ast.ident * Ast.iexpr) list;
}

val analyze_node :
  build:Automata_generation.automata_build ->
  node:Normalized_program.node ->
  analysis
