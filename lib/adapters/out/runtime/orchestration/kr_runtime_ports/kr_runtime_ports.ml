module Verification = struct
  include Runtime_flow

end

module C_generation = struct
  let generate_c ~(input : Kr_engine.Kr_engine_inbound_port.verification_input) =
    match
      Kr_c_codegen.Kr_c_codegen_codegen.emit_program input.verification_model
    with
    | Error message -> Error (Kr_engine.Kr_engine_pipeline_error.Flow_error message)
    | Ok files ->
        Ok
          (List.map
             (fun (file : Kr_c_codegen.Kr_c_codegen_codegen.generated_file) ->
               {
                 Kr_engine.Kr_engine_inbound_port.file_name = file.file_name;
                 contents = file.contents;
               })
             files)
end

module Ports = struct
  module Verification = Verification
  module C_generation = C_generation
end

let default_proof_jobs = Runtime_defaults.default_proof_jobs
