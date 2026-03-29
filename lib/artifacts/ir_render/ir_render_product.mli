(** Product exploration renderers exposed through the artifacts layer. *)

type rendered = {
  guarantee_automaton_lines : string list;
  assume_automaton_lines : string list;
  guarantee_automaton_tex : string;
  assume_automaton_tex : string;
  product_tex : string;
  product_tex_explicit : string;
  product_lines : string list;
  obligations_lines : string list;
  guarantee_automaton_dot : string;
  assume_automaton_dot : string;
  product_dot : string;
  product_dot_explicit : string;
}

val render :
  node_name:Ast.ident ->
  analysis:Product_analysis.analysis ->
  rendered

val render_guarantee_automaton :
  node_name:Ast.ident ->
  analysis:Product_analysis.analysis ->
  string * string

val render_program_automaton :
  node_name:Ast.ident ->
  node:Ir.node ->
  string * string
