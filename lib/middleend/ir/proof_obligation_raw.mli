(** Pass 3: IR production.

    Builds a [Proof_obligation_ir.raw_node] directly from an IR node.
    The raw node captures the state machine structure and executable body of
    each transition — it does NOT include Hoare triples (requires/ensures).
    Those are computed separately in pass 4 ([Proof_obligation_annotate]). *)

(** Build a raw IR node directly from an IR node.

    The [pre_k_map] is recomputed from the AST representation of [node]. *)
val build_raw_node : Ir.node -> Proof_obligation_ir.raw_node
