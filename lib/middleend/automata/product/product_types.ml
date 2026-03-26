type product_state = {
  prog_state : Ast.ident;
  assume_state : int;
  guarantee_state : int;
}

type step_class =
  | Safe
  | Bad_assumption
  | Bad_guarantee

type automaton_edge = Automaton_types.transition

type product_step = {
  src : product_state;
  dst : product_state;
  prog_transition : Ir.transition;
  prog_guard : Fo_formula.t;
  assume_edge : automaton_edge;
  assume_guard : Fo_formula.t;
  guarantee_edge : automaton_edge;
  guarantee_guard : Fo_formula.t;
  step_class : step_class;
}

type prune_reason =
  | Incompatible_program_assumption
  | Incompatible_program_guarantee
  | Incompatible_assumption_guarantee

type pruned_step = {
  src : product_state;
  prog_transition : Ir.transition;
  prog_guard : Fo_formula.t;
  assume_edge : automaton_edge;
  assume_src : int;
  assume_dst : int;
  assume_guard : Fo_formula.t;
  guarantee_edge : automaton_edge;
  guarantee_src : int;
  guarantee_dst : int;
  guarantee_guard : Fo_formula.t;
  reason : prune_reason;
}

type exploration = {
  initial_state : product_state;
  states : product_state list;
  steps : product_step list;
  pruned_steps : pruned_step list;
}

let compare_state a b =
  match String.compare a.prog_state b.prog_state with
  | 0 -> begin
      match Int.compare a.assume_state b.assume_state with
      | 0 -> Int.compare a.guarantee_state b.guarantee_state
      | c -> c
    end
  | c -> c
