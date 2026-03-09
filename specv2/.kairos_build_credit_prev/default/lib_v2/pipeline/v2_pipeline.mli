(** v2 pipeline entry point.
    Internal structure follows Rocq blueprint modules;
    external components are delegated to adapters. *)

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

val run : config -> (unit, string) result
