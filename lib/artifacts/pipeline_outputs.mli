(** Full output assembly for the imported/main pipeline. *)

val with_why_translation_mode :
  Pipeline_types.why_translation_mode -> (unit -> 'a) -> 'a

val stage_meta :
  Pipeline_types.stage_infos -> (string * (string * string) list) list

val instrumentation_diag_texts :
  Pipeline_types.stage_infos ->
  string * string * string * string * string * string * string * string

val program_automaton_texts : Pipeline_types.ast_stages -> string * string

val build_outputs :
  cfg:Pipeline_types.config ->
  asts:Pipeline_types.ast_stages ->
  infos:Pipeline_types.stage_infos ->
  (Pipeline_types.outputs, Pipeline_types.error) result
