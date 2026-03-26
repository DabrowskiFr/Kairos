open Ast

module Abs = Ir

type ir_nodes = {
  raw_ir_nodes : Proof_obligation_ir.raw_node list;
  annotated_ir_nodes : Proof_obligation_ir.annotated_node list;
  verified_ir_nodes : Proof_obligation_ir.verified_node list;
  kernel_ir_nodes : Proof_kernel_types.node_ir list;
}

let build_ast_with_info ~input_file () :
    (Pipeline_types.ast_stages * Pipeline_types.stage_infos, Pipeline_types.error)
    result =
  Provenance.reset ();
  try
    let source, parse_info = Parse_file.parse_source_file_with_info input_file in
    let p_parsed = source.nodes in
    let p_automaton, automata, automata_info =
      Automata_pass.Pass.run_with_info p_parsed ()
    in
    let p_contracts, _automata, contracts_info =
      Contracts_pass.Pass.run_with_info p_automaton automata
    in
    let p_monitor, automata, instrumentation_info =
      Instrumentation_pass.Pass.run_with_info p_contracts automata
    in
    let asts : Pipeline_types.ast_stages =
      {
        source;
        parsed = p_parsed;
        automata_generation = p_automaton;
        automata;
        contracts = p_contracts;
        instrumentation = p_monitor;
      }
    in
    let infos : Pipeline_types.stage_infos =
      {
        parse = Some parse_info;
        automata_generation = Some automata_info;
        contracts = Some contracts_info;
        instrumentation = Some instrumentation_info;
      }
    in
    Ok (asts, infos)
  with exn -> Error (Pipeline_types.Stage_error (Printexc.to_string exn))

let dump_ir_nodes ~input_file : (ir_nodes, Pipeline_types.error) result =
  match build_ast_with_info ~input_file () with
  | Error _ as e -> e
  | Ok (_asts, infos) ->
      let i = Option.value infos.instrumentation ~default:Stage_info.empty_instrumentation_info in
      Ok
        {
          raw_ir_nodes = i.raw_ir_nodes;
          annotated_ir_nodes = i.annotated_ir_nodes;
          verified_ir_nodes = i.verified_ir_nodes;
          kernel_ir_nodes = i.kernel_ir_nodes;
        }

let compile_object ~input_file : (Kairos_object.t, Pipeline_types.error) result =
  match build_ast_with_info ~input_file () with
  | Error _ as err -> err
  | Ok (asts, infos) ->
      let parse_info = Option.value infos.parse ~default:Stage_info.empty_parse_info in
      let instrumentation_info =
        Option.value infos.instrumentation ~default:Stage_info.empty_instrumentation_info
      in
      Kairos_object.build ~source_path:input_file ~source_hash:parse_info.text_hash
        ~imports:(Source_file.imported_paths asts.source) ~program:asts.parsed
        ~runtime_program:(List.map Abs.to_ast_node asts.instrumentation)
        ~kernel_ir_nodes:instrumentation_info.kernel_ir_nodes
      |> Result.map_error (fun msg -> Pipeline_types.Stage_error msg)
