type metadata = {
  format : string;
  format_version : int;
  backend_agnostic : bool;
  source_path : string option;
  source_hash : string option;
  imports : string list;
}
[@@deriving yojson]

type t = {
  metadata : metadata;
  nodes : Product_kernel_ir.exported_node_summary_ir list;
}
[@@deriving yojson]

val current_format : string
val current_version : int

val build :
  source_path:string ->
  source_hash:string option ->
  imports:string list ->
  program:Ast.program ->
  runtime_program:Ast.program ->
  kernel_ir_nodes:Product_kernel_ir.node_ir list ->
  (t, string) result

val summaries : t -> Product_kernel_ir.exported_node_summary_ir list
val write_file : path:string -> t -> (unit, string) result
val read_file : path:string -> (t, string) result
