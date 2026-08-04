(** Implementation of the inbound port using the configured outbound ports. *)

module Make (Ports : Outbound_ports.S) : Inbound_port.S
