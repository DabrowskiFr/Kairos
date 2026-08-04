(** Machine-readable C interface manifest for generated Kairos nodes. *)

val manifest_name_of_header : string -> string

val emit :
  header_name:string ->
  Kr_domain_core_model.program_model ->
  string

