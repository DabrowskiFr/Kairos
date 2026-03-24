val string_of_qid : Why3.Ptree.qualid -> string
val string_of_const : Why3.Constant.constant -> string
val string_of_relop : Ast.relop -> string
val string_of_iexpr : ?ctx:int -> Ast.iexpr -> string
val string_of_hexpr : Ast.hexpr -> string
val string_of_fo : ?ctx:int -> Ast.fo -> string
val string_of_ltl : ?ctx:int -> Ast.ltl -> string
