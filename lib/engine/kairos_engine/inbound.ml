module Make (Ports : Outbound_ports.S) = struct
  let instrumentation_pass = Ports.Pipeline.instrumentation_pass
  let why_pass = Ports.Pipeline.why_pass
  let obligations_pass = Ports.Pipeline.obligations_pass
  let cost_report = Ports.Pipeline.cost_report
  let normalized_program = Ports.Pipeline.normalized_program
  let ir_pretty_dump = Ports.Pipeline.ir_pretty_dump
  let run = Ports.Pipeline.run
  let run_with_callbacks = Ports.Pipeline.run_with_callbacks
  let generate_c = Ports.Pipeline.generate_c
end
