type config = {
  dump_dot : string option;
  dump_dot_short : string option;
  dump_obc : string option;
  dump_why3_vc : string option;
  dump_smt2 : string option;
  dump_ast_stage : Stage_names.stage_id option;
  dump_ast_out : string option;
  dump_ast_all : string option;
  dump_ast_stable : bool;
  check_ast : bool;
  output_file : string option;
  prove : bool;
  prover : string;
  prover_cmd : string option;
  wp_only : bool;
  smoke_tests : bool;
  prefix_fields : bool;
  input_file : string;
}
(* CLI-oriented configuration for dumping stages and running proofs. *)

val run : config -> (unit, string) result
(* Run the pipeline according to the CLI configuration. *)
