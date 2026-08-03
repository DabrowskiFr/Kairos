(** Canonical contracts of the engine's inbound hexagonal port.

    Driving adapters depend on this module. The concrete service is assembled
    outside the engine by the composition root. *)

module Contract = Engine_contract

type config = Contract.config
type error = Contract.error
type verification_input = Inbound_port.verification_input
type generated_file = Inbound_port.generated_file = {
  file_name : string;
  contents : string;
}

val error_to_string : error -> string

module type INBOUND = sig
  include Inbound_port.S
end
