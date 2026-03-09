type run_config = {
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

val run_with_native_pipeline : run_config -> (unit, string) result
