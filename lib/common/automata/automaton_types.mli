(** Semantic automata data shared by the middle-end.

    This module describes:
    {ul
    {- semantic transition guards;}
    {- normalized automata;}
    {- per-node automata generation results.}} *)

(** Boolean guard carried by an automaton transition.

    Guards are stored directly as Kairos expressions, not as atom names or HOA
    labels. *)
type guard = Ast.iexpr

(** Transition represented as [(src_index, guard, dst_index)]. *)
type transition = int * guard * int

(** Safety automaton.

    The record contains:
    {ul
    {- the atom names used during automaton construction;}
    {- raw states and transitions;}
    {- normalized states and transitions;}
    {- grouped transitions for downstream consumers.}} *)
type automaton = {
  atom_names : Ast.ident list;
  states_raw : Ast.ltl list;
  transitions_raw : transition list;
  states : Ast.ltl list;
  transitions : transition list;
  grouped : transition list;
}

(** Mapping between source-level atomic formulas and the fresh atom names used
    while building temporal automata. *)
type automata_atoms = {
  atom_map : (Ast.fo_atom * Ast.ident) list;
  atom_named_exprs : (Ast.ident * Ast.iexpr) list;
}

(** Per-node automata generation result.

    A node carries:
    {ul
    {- one guarantee automaton;}
    {- zero or one assumption automaton;}
    {- the atom maps used to build them.}} *)
type automata_build = {
  atoms : automata_atoms;
  guarantee_atom_names : Ast.ident list;
  guarantee_spec : Ast.ltl;
  guarantee_automaton : automaton;
  assume_atoms : automata_atoms option;
  assume_atom_names : Ast.ident list;
  assume_spec : Ast.ltl option;
  assume_automaton : automaton option;
}

(** Program-wide collection of per-node automata builds, indexed by node name. *)
type node_builds = (Ast.ident * automata_build) list
