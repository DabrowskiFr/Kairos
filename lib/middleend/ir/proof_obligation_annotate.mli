(*---------------------------------------------------------------------------
 * Kairos — Pass 4: Triple computation.
 *
 * Adds Hoare triples (requires/ensures) to a [Proof_obligation_ir.raw_node],
 * producing a [Proof_obligation_ir.annotated_node].
 *
 * The formulas may still contain [Ast.hexpr] references (prev^k x);
 * history elimination is performed in pass 5 ([Proof_obligation_lowering]).
 *---------------------------------------------------------------------------*)

(** Materializes already-generated pre/postconditions onto raw IR nodes. *)

(** Annotate a raw node with Hoare triples.

    [raw] is the output of pass 3 ([Proof_obligation_raw.build_raw_node]).
    [node] is the corresponding finalized abstract node (post-instrumentation).
    Its transitions already carry the generated postconditions and derived
    preconditions computed in the abstract pipeline, so this phase only
    transfers them onto the IR. [analysis] is kept for compatibility with the
    surrounding pipeline. *)
val annotate :
  raw:Proof_obligation_ir.raw_node ->
  node:Ir.node ->
  analysis:Product_build.analysis ->
  Proof_obligation_ir.annotated_node
