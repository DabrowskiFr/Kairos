(** Pass 3: IR production.

    Builds a [Proof_obligation_ir.raw_node] from a finalized instrumented abstract node.
    The raw node captures the state machine structure and executable body of
    each transition — it does NOT include Hoare triples (requires/ensures).
    Those are computed separately in pass 4 (Triple_annotation). *)

(** Build a raw IR node from a finalized instrumented abstract node.

    The [node] argument must be the result of
    [Normalized_instrumentation.finalize_instrumented_abstract_node]. The [pre_k_map] is
    recomputed from the AST representation of [node]. *)
val build_raw_node : Normalized_program.node -> Proof_obligation_ir.raw_node
