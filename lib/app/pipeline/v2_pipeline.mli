(** v2 pipeline entry point.
    Internal structure follows Rocq blueprint modules;
    external components are delegated to adapters. *)

type config = {
  input_file : string;
  dump_why : string option;
  dump_why3_vc : string option;
  dump_smt2 : string option;
  why_translation_mode : Pipeline.why_translation_mode;
  prove : bool;
  prover : string;
  prover_cmd : string option;
}

val run : config -> (unit, string) result
