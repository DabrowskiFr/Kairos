module Contract = Engine_contract

type config = Contract.config
type error = Contract.error
type verification_input = Outbound_ports.verification_input
type generated_file = Outbound_ports.generated_file = {
  file_name : string;
  contents : string;
}

let error_to_string = Contract.error_to_string

module type INBOUND = sig
  include Outbound_ports.PIPELINE
end
