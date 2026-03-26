val solver_enabled : unit -> bool
val prove_formula : Ast.ltl -> bool option
val unsat_formula : Ast.ltl -> bool option
val implies_formula : Ast.ltl -> Ast.ltl -> bool option
