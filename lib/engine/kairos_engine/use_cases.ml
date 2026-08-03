module Make (Ports : Outbound_ports.S) = struct
  include Ports.Verification
  let generate_c = Ports.C_generation.generate_c
end
