include Generated_names

type pre_k_info = Temporal_support.pre_k_info = {
  h : Ast.hexpr;
  expr : Ast.iexpr;
  names : string list;
  vty : Ast.ty;
}

type ltl_norm = Temporal_support.ltl_norm = {
  ltl : Ast.ltl;
  k_guard : int option;
}

let max_x_depth = Temporal_support.max_x_depth
let ltl_of_fo = Temporal_support.ltl_of_fo
let fo_of_ltl = Temporal_support.fo_of_ltl
let is_const_iexpr = Temporal_support.is_const_iexpr
let shift_hexpr_by = Temporal_support.shift_hexpr_by
let normalize_ltl_for_k = Temporal_support.normalize_ltl_for_k
let shift_ltl_by = Temporal_support.shift_ltl_by

include Ast_pretty
include Why_term_support
