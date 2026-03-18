(** Independent v2 pipeline core (no call to [Pipeline.run]). *)

val instrumentation_pass :
  generate_png:bool -> input_file:string -> (Pipeline.automata_outputs, Pipeline.error) result

val why_pass :
  prefix_fields:bool -> input_file:string -> (Pipeline.why_outputs, Pipeline.error) result

val obligations_pass :
  prefix_fields:bool -> prover:string -> input_file:string ->
  (Pipeline.obligations_outputs, Pipeline.error) result

val compile_object : input_file:string -> (Kairos_object.t, Pipeline.error) result

type ir_nodes = {
  raw_ir_nodes : Kairos_ir.raw_node list;
  annotated_ir_nodes : Kairos_ir.annotated_node list;
  verified_ir_nodes : Kairos_ir.verified_node list;
  kernel_ir_nodes : Product_kernel_ir.node_ir list;
}

val dump_ir_nodes : input_file:string -> (ir_nodes, Pipeline.error) result

val eval_pass :
  input_file:string -> trace_text:string -> with_state:bool -> with_locals:bool ->
  (string, Pipeline.error) result

val run : Pipeline.config -> (Pipeline.outputs, Pipeline.error) result

val run_with_callbacks :
  should_cancel:(unit -> bool) ->
  Pipeline.config ->
  on_outputs_ready:(Pipeline.outputs -> unit) ->
  on_goals_ready:(string list * int list -> unit) ->
  on_goal_done:(int -> string -> string -> float -> string option -> string -> string option -> unit) ->
  (Pipeline.outputs, Pipeline.error) result
