(** Concrete outgoing adapters used by the default Kairos composition. *)

module Ports : Kr_engine.Kr_engine_outbound_ports.S

val default_proof_jobs : unit -> int
