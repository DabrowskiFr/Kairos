type source_diagnostic = {
  line : int;
  column : int;
  line_end : int;
  column_end : int;
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

type frontend_summary = {
  node_count : int;
  assume_count : int;
  guarantee_count : int;
}

val source_diagnostics : filename:string -> text:string -> source_diagnostic list
val semantic_symbols : filename:string -> text:string -> semantic_symbols option
val surface_dump : input_file:string -> (string, Kr_engine.Api.Contract.error) result
val elaborated_dump : input_file:string -> (string, Kr_engine.Api.Contract.error) result
val frontend_summary : input_file:string -> (frontend_summary, Kr_engine.Api.Contract.error) result
