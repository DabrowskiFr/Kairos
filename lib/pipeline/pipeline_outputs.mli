(** Full output assembly for the imported/main pipeline. *)

val with_why_translation_mode :
  Pipeline.why_translation_mode -> (unit -> 'a) -> 'a

val stage_meta :
  Pipeline.stage_infos -> (string * (string * string) list) list

val instrumentation_diag_texts :
  Pipeline.stage_infos ->
  string * string * string * string * string * string * string * string

val program_automaton_texts : Pipeline.ast_stages -> string * string

val build_outputs :
  cfg:Pipeline.config ->
  asts:Pipeline.ast_stages ->
  infos:Pipeline.stage_infos ->
  (Pipeline.outputs, Pipeline.error) result
