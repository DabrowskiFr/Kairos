(*---------------------------------------------------------------------------
 * Kairos — Pass 5: History elimination.
 *
 * Substitutes all [Ast.hexpr] references of the form [prev^k x] (i.e.
 * [HPreK(x, k)]) with the corresponding ghost local variable
 * [IVar "__pre_k{k}_x"], producing a [Kairos_ir.verified_node] that is
 * ready for trivial structural Why3 emission.
 *
 * The pass also:
 * - appends the introduced [__pre_k{k}_x] variables to the node's locals;
 * - attaches the shift+capture statements to every transition's
 *   [pre_k_updates] field.
 *---------------------------------------------------------------------------*)

(** Eliminate history references from an annotated node.

    Every occurrence of [HPreK(x, k)] in requires, ensures, coherency_goals,
    and state_invariants is replaced by [HNow (IVar "__pre_k{k}_x")].
    The shift statements (e.g. [__pre_k2_x := __pre_k1_x; __pre_k1_x := x])
    are stored in [verified_transition.pre_k_updates].
    The extra locals ([__pre_k{k}_x] variables) are appended to
    [verified_node.locals].

    Formulas whose [HPreK] references are NOT found in [raw.pre_k_map] are
    kept verbatim (the substitution is applied on a best-effort basis). *)
val eliminate : Kairos_ir.annotated_node -> Kairos_ir.verified_node
