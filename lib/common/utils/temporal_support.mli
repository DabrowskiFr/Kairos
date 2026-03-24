type pre_k_info = { h : Ast.hexpr; expr : Ast.iexpr; names : string list; vty : Ast.ty }
[@@deriving yojson]

type ltl_norm = { ltl : Ast.ltl; k_guard : int option }

val max_x_depth : Ast.ltl -> int
val ltl_of_fo : Ast.fo -> Ast.ltl
val fo_of_ltl : Ast.ltl -> Ast.fo
val is_const_iexpr : Ast.iexpr -> bool
val shift_hexpr_by : init_for_var:(Ast.ident -> Ast.iexpr) -> int -> Ast.hexpr -> Ast.hexpr option
val normalize_ltl_for_k : init_for_var:(Ast.ident -> Ast.iexpr) -> Ast.ltl -> ltl_norm
val shift_ltl_by : init_for_var:(Ast.ident -> Ast.iexpr) -> int -> Ast.ltl -> Ast.ltl option
