(** Concrete outgoing adapters used by the default Kairos composition. *)

module Ports : Kr_engine.Outbound_ports.S

val default_proof_jobs : unit -> int
