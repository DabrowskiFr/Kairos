(** Trace evaluator for a single top-level Kairos node. *)

val eval_pass :
  input_file:string ->
  trace_text:string ->
  with_state:bool ->
  with_locals:bool ->
  (string, Pipeline_api_types.error) result
