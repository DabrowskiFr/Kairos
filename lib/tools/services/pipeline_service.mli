(** Pipeline orchestration service built on top of specialized pipeline modules. *)

val instrumentation_pass :
  generate_png:bool ->
  input_file:string ->
  (Pipeline_types.automata_outputs, Pipeline_types.error) result

val why_pass :
  prefix_fields:bool ->
  input_file:string ->
  (Pipeline_types.why_outputs, Pipeline_types.error) result

val obligations_pass :
  prefix_fields:bool ->
  prover:string ->
  input_file:string ->
  (Pipeline_types.obligations_outputs, Pipeline_types.error) result

val normalized_program : input_file:string -> (string, Pipeline_types.error) result

val compile_object : input_file:string -> (Kairos_object.t, Pipeline_types.error) result

type ir_nodes = Pipeline_build.ir_nodes = {
  raw_ir_nodes : Ir.raw_node list;
  annotated_ir_nodes : Ir.annotated_node list;
  verified_ir_nodes : Ir.verified_node list;
  kernel_ir_nodes : Proof_kernel_types.node_ir list;
}

val dump_ir_nodes : input_file:string -> (ir_nodes, Pipeline_types.error) result

val eval_pass :
  input_file:string -> trace_text:string -> with_state:bool -> with_locals:bool ->
  (string, Pipeline_types.error) result

val run : Pipeline_types.config -> (Pipeline_types.outputs, Pipeline_types.error) result

val run_with_callbacks :
  should_cancel:(unit -> bool) ->
  Pipeline_types.config ->
  on_outputs_ready:(Pipeline_types.outputs -> unit) ->
  on_goals_ready:(string list * int list -> unit) ->
  on_goal_done:(int -> string -> string -> float -> string option -> string -> string option -> unit) ->
  (Pipeline_types.outputs, Pipeline_types.error) result
