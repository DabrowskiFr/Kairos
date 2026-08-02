(** Concrete driven adapters used by the default Kairos composition. *)

module Ports : Kairos_engine.Outbound_ports.S

val default_proof_jobs : unit -> int
