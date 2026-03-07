type product_state = {
  prog_state : Ast.ident;
  assume_state : int;
  guarantee_state : int;
}

type step_class =
  | Safe
  | Bad_assumption
  | Bad_guarantee

type automaton_edge = Automaton_engine.transition

type product_step = {
  src : product_state;
  dst : product_state;
  prog_transition : Abstract_model.transition;
  prog_guard : Ast.fo;
  assume_edge : automaton_edge;
  assume_guard : Ast.fo;
  guarantee_edge : automaton_edge;
  guarantee_guard : Ast.fo;
  step_class : step_class;
}

type prune_reason =
  | Incompatible_program_assumption
  | Incompatible_program_guarantee
  | Incompatible_assumption_guarantee

type pruned_step = {
  src : product_state;
  prog_transition : Abstract_model.transition;
  prog_guard : Ast.fo;
  assume_edge : automaton_edge;
  assume_src : int;
  assume_dst : int;
  assume_guard : Ast.fo;
  guarantee_edge : automaton_edge;
  guarantee_src : int;
  guarantee_dst : int;
  guarantee_guard : Ast.fo;
  reason : prune_reason;
}

type exploration = {
  initial_state : product_state;
  states : product_state list;
  steps : product_step list;
  pruned_steps : pruned_step list;
}

val compare_state : product_state -> product_state -> int
