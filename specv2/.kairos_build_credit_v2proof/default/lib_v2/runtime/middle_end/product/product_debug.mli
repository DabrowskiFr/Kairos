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
