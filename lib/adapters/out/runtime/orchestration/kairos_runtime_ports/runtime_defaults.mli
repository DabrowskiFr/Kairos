val default_proof_jobs : unit -> int
(** Default number of parallel prover calls for proof-oriented runs.

    The value is derived from the CPU topology when the operating system
    exposes performance-core information, and otherwise from the runtime
    available parallelism while leaving one execution context free when
    possible. *)
