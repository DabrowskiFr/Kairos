(** Result of the explicit product exploration for one normalized node.

    The analysis keeps both the reachable product graph itself and the metadata
    needed later by renderers and proof-export passes:
    - indices of the bad states in the assumption and guarantee automata;
    - printable labels for automaton states;
    - grouped automaton edges as they were built upstream;
    - atom tables used to recover readable guards. *)

(** Full exploration result together with auxiliary automata metadata. *)
type analysis = {
  (** Reachable product states and explicit product steps. *)
  exploration : Product_types.exploration;
  (** Index of the bad assumption state, or [-1] when no bad state exists. *)
  assume_bad_idx : int;
  (** Index of the bad guarantee state, or [-1] when no bad state exists. *)
  guarantee_bad_idx : int;
  (** Human-readable labels for guarantee-automaton states. *)
  guarantee_state_labels : string list;
  (** Human-readable labels for assumption-automaton states. *)
  assume_state_labels : string list;
  (** Grouped edges of the guarantee automaton. *)
  guarantee_grouped_edges : Automaton_types.transition list;
  (** Grouped edges of the assumption automaton. *)
  assume_grouped_edges : Automaton_types.transition list;
  (** Atom-name table used to render guarantee guards. *)
  guarantee_atom_map_exprs : (Ast.ident * Ast.iexpr) list;
  (** Atom-name table used to render assumption guards. *)
  assume_atom_map_exprs : (Ast.ident * Ast.iexpr) list;
}
