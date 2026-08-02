module Pipeline = struct
  include Runtime_flow

  let generate_c ~(input : Kairos_engine.Outbound_ports.verification_input) =
    match
      Kairos_c_codegen.C_codegen.emit_program input.verification_model
    with
    | Error message -> Error (Kairos_engine.Pipeline_error.Flow_error message)
    | Ok files ->
        Ok
          (List.map
             (fun (file : Kairos_c_codegen.C_codegen.generated_file) ->
               {
                 Kairos_engine.Outbound_ports.file_name = file.file_name;
                 contents = file.contents;
               })
             files)
end

module Ports = struct
  module Pipeline = Pipeline
end

let default_proof_jobs = Runtime_defaults.default_proof_jobs
