type env = {
  rec_name : string;
  rec_vars : string list;
  var_map : (Ast.ident * Ast.ident) list;
  links : (Ast.hexpr * Ast.ident) list;
  pre_k : (Ast.hexpr * Temporal_support.pre_k_info) list;
  inst_map : (Ast.ident * Ast.ident) list;
  inputs : Ast.ident list;
}

val loc : Why3.Loc.position
val ident : string -> Why3.Ptree.ident
val infix_ident : string -> Why3.Ptree.ident
val qid1 : string -> Why3.Ptree.qualid
val qdot : Why3.Ptree.qualid -> string -> Why3.Ptree.qualid
val mk_expr : Why3.Ptree.expr_desc -> Why3.Ptree.expr
val mk_term : Why3.Ptree.term_desc -> Why3.Ptree.term
val term_eq : Why3.Ptree.term -> Why3.Ptree.term -> Why3.Ptree.term
val term_neq : Why3.Ptree.term -> Why3.Ptree.term -> Why3.Ptree.term
val term_bool_binop : Why3.Dterm.dbinop -> Why3.Ptree.term -> Why3.Ptree.term -> Why3.Ptree.term
val term_implies : Why3.Ptree.term -> Why3.Ptree.term -> Why3.Ptree.term
val term_old : Why3.Ptree.term -> Why3.Ptree.term
val apply_expr : Why3.Ptree.expr -> Why3.Ptree.expr list -> Why3.Ptree.expr
val default_pty : Ast.ty -> Why3.Ptree.pty
val binop_id : Ast.binop -> string
val rec_var_name : env -> Ast.ident -> Ast.ident
val field : env -> Ast.ident -> Why3.Ptree.expr
val is_rec_var : env -> Ast.ident -> bool
val term_var : env -> Ast.ident -> Why3.Ptree.term_desc
val find_link : env -> Ast.hexpr -> Ast.ident option
val find_pre_k : env -> Ast.hexpr -> Temporal_support.pre_k_info option
val normalize_infix : string -> string
val string_of_term : Why3.Ptree.term -> string
val uniq_terms : Why3.Ptree.term list -> Why3.Ptree.term list
val simplify_term_bool : Why3.Ptree.term -> Why3.Ptree.term
val term_of_var : env -> Ast.ident -> Why3.Ptree.term
val relop_id : Ast.relop -> string
val term_of_instance_var : env -> Ast.ident -> Ast.ident -> Ast.ident -> Why3.Ptree.term
val expr_of_instance_var : env -> Ast.ident -> Ast.ident -> Ast.ident -> Why3.Ptree.expr
