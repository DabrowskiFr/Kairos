(** Concrete assembly of source parsing and the engine's driven ports. *)

val error_of_frontend :
  Kairos_lang.Frontend.error -> Kairos_engine.Api.error

val instrumentation_pass :
  generate_png:bool ->
  input_file:string ->
  (Kairos_engine.Api.Contract.automata_outputs, Kairos_engine.Api.error) result

val why_pass :
  proof_optimizations:Kairos_engine.Api.Contract.proof_optimizations ->
  input_file:string ->
  (Kairos_engine.Api.Contract.why_outputs, Kairos_engine.Api.error) result

val obligations_pass :
  proof_optimizations:Kairos_engine.Api.Contract.proof_optimizations ->
  input_file:string ->
  (Kairos_engine.Api.Contract.obligations_outputs, Kairos_engine.Api.error) result

val cost_report :
  proof_optimizations:Kairos_engine.Api.Contract.proof_optimizations ->
  input_file:string ->
  (Kairos_engine.Api.Contract.cost_report_outputs, Kairos_engine.Api.error) result

val normalized_program :
  proof_optimizations:Kairos_engine.Api.Contract.proof_optimizations ->
  input_file:string ->
  (string, Kairos_engine.Api.error) result

val ir_pretty_dump :
  proof_optimizations:Kairos_engine.Api.Contract.proof_optimizations ->
  input_file:string ->
  (string, Kairos_engine.Api.error) result

val generate_c :
  input_file:string ->
  (Kairos_engine.Api.generated_file list, Kairos_engine.Api.error) result

val run :
  Kairos_engine.Api.config ->
  (Kairos_engine.Api.Contract.outputs, Kairos_engine.Api.error) result

val run_with_callbacks :
  should_cancel:(unit -> bool) ->
  Kairos_engine.Api.config ->
  on_outputs_ready:(Kairos_engine.Api.Contract.outputs -> unit) ->
  on_goals_ready:(string list * int list -> unit) ->
  on_goal_done:
    (int -> string -> string -> float -> string option -> string option -> unit) ->
  (Kairos_engine.Api.Contract.outputs, Kairos_engine.Api.error) result
