(** Source-oriented services that do not expose frontend ASTs. *)

type source_diagnostic = {
  line : int;
  column : int;
  severity : int;
  source : string;
  message : string;
}

type semantic_symbols = {
  all : string list;
  nodes : string list;
  states : string list;
  variables : string list;
}

val diagnostics :
  filename:string ->
  text:string ->
  source_diagnostic list

val semantic_symbols :
  filename:string ->
  text:string ->
  semantic_symbols option

val surface_dump :
  input_file:string ->
  (string, Kairos_frontend.error) result

val elaborated_dump :
  input_file:string ->
  (string, Kairos_frontend.error) result
