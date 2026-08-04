(** Concrete assembly of source parsing and the engine's driven ports. *)

val error_of_frontend :
  Kr_lang.Kr_lang_frontend.error -> Kr_engine.Api.error

val instrumentation_pass :
  generate_png:bool ->
  input_file:string ->
  (Kr_engine.Api.Contract.automata_outputs, Kr_engine.Api.error) result

val why_pass :
  proof_optimizations:Kr_engine.Api.Contract.proof_optimizations ->
  input_file:string ->
  (Kr_engine.Api.Contract.why_outputs, Kr_engine.Api.error) result

val obligations_pass :
  proof_optimizations:Kr_engine.Api.Contract.proof_optimizations ->
  input_file:string ->
  (Kr_engine.Api.Contract.obligations_outputs, Kr_engine.Api.error) result

val cost_report :
  proof_optimizations:Kr_engine.Api.Contract.proof_optimizations ->
  input_file:string ->
  (Kr_engine.Api.Contract.cost_report_outputs, Kr_engine.Api.error) result

val normalized_program :
  proof_optimizations:Kr_engine.Api.Contract.proof_optimizations ->
  input_file:string ->
  (string, Kr_engine.Api.error) result

val ir_pretty_dump :
  proof_optimizations:Kr_engine.Api.Contract.proof_optimizations ->
  input_file:string ->
  (string, Kr_engine.Api.error) result

val generate_c :
  input_file:string ->
  (Kr_engine.Api.generated_file list, Kr_engine.Api.error) result

val run :
  Kr_engine.Api.config ->
  (Kr_engine.Api.Contract.outputs, Kr_engine.Api.error) result

val run_with_callbacks :
  should_cancel:(unit -> bool) ->
  Kr_engine.Api.config ->
  on_outputs_ready:(Kr_engine.Api.Contract.outputs -> unit) ->
  on_goals_ready:(string list * int list -> unit) ->
  on_goal_done:
    (int -> string -> string -> float -> string option -> string option -> unit) ->
  (Kr_engine.Api.Contract.outputs, Kr_engine.Api.error) result
