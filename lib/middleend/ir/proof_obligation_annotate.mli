(*---------------------------------------------------------------------------
 * Kairos — Pass 4: Triple computation.
 *
 * Adds Hoare triples (requires/ensures) to a [Ir.raw_node],
 * producing a [Ir.annotated_node].
 *
 * The formulas may still contain [Ast.hexpr] references (prev^k x);
 * history elimination is performed in pass 5 ([Proof_obligation_lowering]).
 *---------------------------------------------------------------------------*)

(** Materializes already-generated pre/postconditions onto the raw view stored
    inside the IR. *)

val apply_node : analysis:Product_build.analysis -> Ir.node -> Ir.node
val apply_program : analyses:(Ast.ident * Product_build.analysis) list -> Ir.node list -> Ir.node list
