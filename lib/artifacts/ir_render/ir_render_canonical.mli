(** Renderers for the canonical proof-step structure built from reachable
    product sources and program transitions. *)

type rendered = {
  canonical_lines : string list;
  canonical_tex : string;
  canonical_dot : string;
}

val render :
  node_name:Ast.ident ->
  analysis:Product_analysis.analysis ->
  node:Ir.node ->
  rendered
