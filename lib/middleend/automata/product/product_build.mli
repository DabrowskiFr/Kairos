(** Explicit construction of the product between:
    - the normalized program control graph of one node;
    - the assumption automaton;
    - the guarantee automaton.

    The builder explores reachable triples [(P, A, G)] from the initial state
    and records one {!Product_types.product_step} for every local combination of
    program transition, assumption edge, and guarantee edge. *)

(** Alias used by downstream code. *)
type analysis = Product_analysis.analysis

val analyze_node :
  build:Automaton_types.automata_build ->
  node:Ir.node ->
  analysis
(** [analyze_node ~build ~node] explores the explicit product associated with
    [node] using the automata already built in [build].

    The result contains:
    - the reachable product states;
    - the explicit product steps between them;
    - the bad-state indices and rendering metadata required downstream. *)
