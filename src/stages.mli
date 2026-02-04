type config = {
  dump_dot : string option;
  dump_dot_short : string option;
  dump_obc : string option;
  dump_why3_vc : string option;
  dump_smt2 : string option;
  dump_ast_stage : Stage_names.stage_id option;
  dump_ast_out : string option;
  dump_ast_all : string option;
  output_file : string option;
  prove : bool;
  prover : string;
  prefix_fields : bool;
  input_file : string;
}

val run : config -> (unit, string) result
