type generated_file = Kr_engine.Api.generated_file = {
  file_name : string;
  contents : string;
}

val generate_c : input_file:string -> (generated_file list, Kr_engine.Api.Contract.error) result
