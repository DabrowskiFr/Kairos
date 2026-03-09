type run_config = Rocq_end_to_end.run_config = {
  input_file : string;
  dump_obc : string option;
  dump_obc_abstract : bool;
  dump_why : string option;
  dump_why3_vc : string option;
  dump_smt2 : string option;
  prove : bool;
  prover : string;
  prover_cmd : string option;
}

let run_with_native_pipeline (cfg : run_config) : (unit, string) result = Rocq_end_to_end.run cfg
