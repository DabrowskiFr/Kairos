(** Full output assembly for the imported/main pipeline. *)

val with_why_translation_mode :
  Pipeline_api_types.why_translation_mode -> (unit -> 'a) -> 'a

val stage_meta :
  Pipeline_api_types.stage_infos -> (string * (string * string) list) list

val instrumentation_diag_texts :
  Pipeline_api_types.stage_infos ->
  string * string * string * string * string * string * string * string

val program_automaton_texts : Pipeline_api_types.ast_stages -> string * string

val build_outputs :
  cfg:Pipeline_api_types.config ->
  asts:Pipeline_api_types.ast_stages ->
  infos:Pipeline_api_types.stage_infos ->
  (Pipeline_api_types.outputs, Pipeline_api_types.error) result
