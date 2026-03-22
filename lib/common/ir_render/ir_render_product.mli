(** Product exploration renderers exposed through the artifacts layer. *)

type rendered = {
  guarantee_automaton_lines : string list;
  assume_automaton_lines : string list;
  product_lines : string list;
  obligations_lines : string list;
  prune_lines : string list;
  guarantee_automaton_dot : string;
  assume_automaton_dot : string;
  product_dot : string;
}

val render :
  node_name:Ast.ident ->
  analysis:Product_build.analysis ->
  rendered

val render_guarantee_automaton :
  node_name:Ast.ident ->
  analysis:Product_build.analysis ->
  string * string

val render_program_automaton :
  node_name:Ast.ident ->
  node:Normalized_program.node ->
  string * string
