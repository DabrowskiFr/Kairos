type ident = Ast.ident
type loc = Ast.loc
type ltl = Ast.ltl
type ltl_o = Ast.ltl_o
type hexpr = Ast.hexpr
type iexpr = Ast.iexpr
type stmt = Ast.stmt
type vdecl = Ast.vdecl
type invariant_user = Ast.invariant_user
type invariant_state_rel = Ast.invariant_state_rel
type node_semantics = Ast.node_semantics
type transition = Ast.transition

type formula_id = int
type transition_index = int
type automaton_state_index = int
type formula_origin_entry = formula_id * Formula_origin.t option
