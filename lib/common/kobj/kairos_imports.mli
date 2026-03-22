(** Loads imported [.kobj] objects and their exported node summaries. *)

type loaded_imports = {
  objects : Kairos_object.t list;
  summaries : Proof_kernel_ir.exported_node_summary_ir list;
  resolved_paths : string list;
}

val load_for_source :
  source_path:string ->
  source:Source_file.t ->
  (loaded_imports, string) result

val object_output_path_of_source : string -> string
