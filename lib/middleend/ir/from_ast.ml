open Ast

let of_ast_contract_formula ?origin (f : Ast.ltl_o) : Ir.contract_formula =
  { logic = f.value; meta = { origin; oid = f.oid; loc = f.loc } }

let of_ast_transition (t : Ast.transition) : Ir.transition =
  {
    src = t.src;
    dst = t.dst;
    guard = t.guard;
    requires = [];
    ensures = [];
    body = t.body;
    warnings = [];
  }

let of_ast_node (n : Ast.node) : Ir.node =
  let semantics = Ast.semantics_of_node n in
  let spec = Ast.specification_of_node n in
  {
    semantics;
    trans = List.map of_ast_transition n.semantics.sem_trans;
    product_transitions = [];
    source_info =
      {
        assumes = spec.spec_assumes;
        guarantees = spec.spec_guarantees;
        user_invariants = [];
        state_invariants = spec.spec_invariants_state_rel;
      };
    coherency_goals = [];
    proof_views = Ir.empty_proof_views;
  }

let of_ast_program (p : Ast.program) : Ir.node list = List.map of_ast_node p
