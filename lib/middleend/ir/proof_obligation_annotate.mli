(*---------------------------------------------------------------------------
 * Kairos — Pass 4: Annotated-view materialization.
 *
 * Builds [Ir.annotated_node] from [Ir.raw_node] while preserving transition
 * structure for diagnostics/export.
 *
 * The formulas may still contain [Ast.hexpr] references (prev^k x);
 * history elimination is performed in pass 5 ([Proof_obligation_lowering]).
 *---------------------------------------------------------------------------*)

(** Materializes the annotated proof view stored inside the IR. *)

val apply_node : analysis:Product_build.analysis -> Ir.node -> Ir.node
val apply_program : analyses:(Ast.ident * Product_build.analysis) list -> Ir.node list -> Ir.node list
