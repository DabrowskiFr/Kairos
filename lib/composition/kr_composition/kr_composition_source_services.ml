module Frontend = Kr_lang.Kr_lang_frontend
module Source_services = Kr_lang.Kr_lang_source_services
module Flow = Internal.Wiring

type source_diagnostic = Source_services.source_diagnostic = {
  line : int;
  column : int;
  line_end : int;
  column_end : int;
  severity : int;
  source : string;
  message : string;
}

type semantic_symbols = Source_services.semantic_symbols = {
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

let source_diagnostics = Source_services.diagnostics
let semantic_symbols = Source_services.semantic_symbols

let surface_dump ~input_file =
  Source_services.surface_dump ~input_file
  |> Result.map_error Flow.error_of_frontend

let elaborated_dump ~input_file =
  Source_services.elaborated_dump ~input_file
  |> Result.map_error Flow.error_of_frontend

let frontend_summary ~input_file =
  match Frontend.parse_input ~input_file with
  | Error error -> Error (Flow.error_of_frontend error)
  | Ok frontend ->
      let nodes = frontend.Frontend.verification_model in
      let count_contracts select =
        nodes
        |> List.map (fun (node : Kr_domain_core.Kr_domain_core_model.node_model) ->
               List.length (select node))
        |> List.fold_left ( + ) 0
      in
      Ok
        {
          node_count = List.length nodes;
          assume_count = count_contracts (fun node -> node.assumes);
          guarantee_count = count_contracts (fun node -> node.guarantees);
        }
