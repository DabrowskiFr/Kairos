(** Pass 5: history elimination over the Kairos IR. *)

(*---------------------------------------------------------------------------
 * Kairos — Pass 5: History elimination.
 *
 * Substitutes all [Ast.hexpr] references of the form [prev^k x] (i.e.
 * [HPreK(x, k)]) with the corresponding ghost local variable
 * [IVar "__pre_k{k}_x"], producing a [Ir.verified_node] that is
 * ready for trivial structural Why3 emission.
 *
 * The pass also:
 * - appends the introduced [__pre_k{k}_x] variables to the node's locals;
 * - attaches the shift+capture statements to every transition's
 *   [pre_k_updates] field.
 *---------------------------------------------------------------------------*)

(** Eliminate history references from the annotated view stored inside the IR. *)

val apply_node : Ir.node -> Ir.node
val apply_program : Ir.node list -> Ir.node list
