module Make (Ports : Kr_engine_outbound_ports.S) = struct
  include Ports.Verification
  let generate_c = Ports.C_generation.generate_c
end
