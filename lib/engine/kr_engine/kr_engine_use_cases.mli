(** Implementation of the inbound port using the configured outbound ports. *)

module Make (Ports : Kr_engine_outbound_ports.S) : Kr_engine_inbound_port.S
