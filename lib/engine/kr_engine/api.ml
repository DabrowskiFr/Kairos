module Contract = Engine_contract

type config = Contract.config
type error = Contract.error
type verification_input = Inbound_port.verification_input
type generated_file = Inbound_port.generated_file = {
  file_name : string;
  contents : string;
}

let error_to_string = Contract.error_to_string

module type INBOUND = sig
  include Inbound_port.S
end
