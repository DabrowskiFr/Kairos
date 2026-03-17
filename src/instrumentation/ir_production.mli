(** Pass 3: IR production.

    Builds a [Kairos_ir.raw_node] from a finalized instrumented abstract node.
    The raw node captures the state machine structure and executable body of
    each transition — it does NOT include Hoare triples (requires/ensures).
    Those are computed separately in pass 4 (Triple_computation). *)

(** Build a raw IR node from a finalized instrumented abstract node.

    The [node] argument must be the result of
    [Instrumentation.finalize_instrumented_abstract_node], i.e. it already
    carries the monitor state update code in [t.attrs.instrumentation] and the
    [__aut_state] local variable.  The [pre_k_map] is recomputed from the AST
    representation of [node]. *)
val build_raw_node : Abstract_model.node -> Kairos_ir.raw_node
