(** Inbound use cases offered by the engine to driving adapters. *)

module Make (Ports : Outbound_ports.S) : sig
  include Outbound_ports.PIPELINE
end
