(** Shared product-analysis result used by renderers and kernel builders. *)

type analysis = {
  exploration : Product_types.exploration;
  assume_bad_idx : int;
  guarantee_bad_idx : int;
  guarantee_state_labels : string list;
  assume_state_labels : string list;
  guarantee_grouped_edges : Automaton_types.transition list;
  assume_grouped_edges : Automaton_types.transition list;
  guarantee_atom_map_exprs : (Ast.ident * Ast.iexpr) list;
  assume_atom_map_exprs : (Ast.ident * Ast.iexpr) list;
}
