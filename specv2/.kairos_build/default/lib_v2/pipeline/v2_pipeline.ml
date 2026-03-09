module Native = V2_native_external_bridge

type config = {
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

let run (cfg : config) : (unit, string) result =
  let external_cfg : Native.run_config =
    {
      input_file = cfg.input_file;
      dump_obc = cfg.dump_obc;
      dump_obc_abstract = cfg.dump_obc_abstract;
      dump_why = cfg.dump_why;
      dump_why3_vc = cfg.dump_why3_vc;
      dump_smt2 = cfg.dump_smt2;
      prove = cfg.prove;
      prover = cfg.prover;
      prover_cmd = cfg.prover_cmd;
    }
  in
  Native.run_with_native_pipeline external_cfg
