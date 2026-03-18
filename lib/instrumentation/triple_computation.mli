(*---------------------------------------------------------------------------
 * Kairos — Pass 4: Triple computation.
 *
 * Adds Hoare triples (requires/ensures) to a [Kairos_ir.raw_node],
 * producing a [Kairos_ir.annotated_node].
 *
 * The formulas may still contain [Ast.hexpr] references (prev^k x);
 * history elimination is performed in pass 5 ([History_elimination]).
 *---------------------------------------------------------------------------*)

(** Annotate a raw node with Hoare triples.

    [raw] is the output of pass 3 ([Ir_production.build_raw_node]).
    [node] is the corresponding finalized abstract node (post-instrumentation).
    It carries the already-computed requires/ensures on each transition:
    user contracts + compatibility invariants added by [apply_contract_pipeline].
    [analysis] is reserved for future use (direct recomputation of
    compat_invariants independently of the abstract node). *)
val annotate :
  raw:Kairos_ir.raw_node ->
  node:Abstract_model.node ->
  analysis:Product_build.analysis ->
  Kairos_ir.annotated_node
