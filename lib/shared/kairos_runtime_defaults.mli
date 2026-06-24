val available_parallelism : unit -> int
(** Number of execution contexts the runtime recommends for CPU-bound work. *)

val default_proof_jobs : unit -> int
(** Default number of parallel prover calls for proof-oriented runs.

    The value is derived from the available parallelism and leaves one execution
    context free when possible. *)
