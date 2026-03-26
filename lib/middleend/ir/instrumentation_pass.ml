open Ast
open Generated_names
open Temporal_support
open Ast_pretty

module Abs = Ir

module RawPass = struct
  type ast_in = Stage_types.contracts_stage
  type ast_out = Stage_types.instrumentation_stage
  type stage_in = Automata_generation.node_builds
  type stage_out = Automata_generation.node_builds
  type info = Stage_info.instrumentation_info

  type info_acc = {
    mutable kernel_ir_nodes_rev : Proof_kernel_types.node_ir list;
    mutable exported_node_summaries_rev : Proof_kernel_types.exported_node_summary_ir list;
    mutable raw_ir_nodes_rev : Proof_obligation_ir.raw_node list;
    mutable annotated_ir_nodes_rev : Proof_obligation_ir.annotated_node list;
    mutable verified_ir_nodes_rev : Proof_obligation_ir.verified_node list;
    mutable kernel_pipeline_lines_rev : string list;
    mutable warnings_rev : string list;
    mutable guarantee_automaton_lines_rev : string list;
    mutable assume_automaton_lines_rev : string list;
    mutable product_lines_rev : string list;
    mutable obligations_lines_rev : string list;
    mutable prune_lines_rev : string list;
    mutable guarantee_automaton_dot : string;
    mutable assume_automaton_dot : string;
    mutable product_dot : string;
  }

  let empty_info_acc () : info_acc =
    {
      kernel_ir_nodes_rev = [];
      exported_node_summaries_rev = [];
      raw_ir_nodes_rev = [];
      annotated_ir_nodes_rev = [];
      verified_ir_nodes_rev = [];
      kernel_pipeline_lines_rev = [];
      warnings_rev = [];
      guarantee_automaton_lines_rev = [];
      assume_automaton_lines_rev = [];
      product_lines_rev = [];
      obligations_lines_rev = [];
      prune_lines_rev = [];
      guarantee_automaton_dot = "";
      assume_automaton_dot = "";
      product_dot = "";
    }

  let add_node_info (acc : info_acc) (node_info : info) : unit =
    acc.kernel_ir_nodes_rev <- List.rev_append node_info.kernel_ir_nodes acc.kernel_ir_nodes_rev;
    acc.exported_node_summaries_rev <-
      List.rev_append node_info.exported_node_summaries acc.exported_node_summaries_rev;
    acc.raw_ir_nodes_rev <- List.rev_append node_info.raw_ir_nodes acc.raw_ir_nodes_rev;
    acc.annotated_ir_nodes_rev <- List.rev_append node_info.annotated_ir_nodes acc.annotated_ir_nodes_rev;
    acc.verified_ir_nodes_rev <- List.rev_append node_info.verified_ir_nodes acc.verified_ir_nodes_rev;
    acc.kernel_pipeline_lines_rev <-
      List.rev_append node_info.kernel_pipeline_lines acc.kernel_pipeline_lines_rev;
    acc.warnings_rev <- List.rev_append node_info.warnings acc.warnings_rev;
    acc.guarantee_automaton_lines_rev <-
      List.rev_append node_info.guarantee_automaton_lines acc.guarantee_automaton_lines_rev;
    acc.assume_automaton_lines_rev <-
      List.rev_append node_info.assume_automaton_lines acc.assume_automaton_lines_rev;
    acc.product_lines_rev <- List.rev_append node_info.product_lines acc.product_lines_rev;
    acc.obligations_lines_rev <- List.rev_append node_info.obligations_lines acc.obligations_lines_rev;
    acc.prune_lines_rev <- List.rev_append node_info.prune_lines acc.prune_lines_rev;
    if acc.guarantee_automaton_dot = "" && node_info.guarantee_automaton_dot <> "" then
      acc.guarantee_automaton_dot <- node_info.guarantee_automaton_dot;
    if acc.assume_automaton_dot = "" && node_info.assume_automaton_dot <> "" then
      acc.assume_automaton_dot <- node_info.assume_automaton_dot;
    if acc.product_dot = "" && node_info.product_dot <> "" then acc.product_dot <- node_info.product_dot

  let freeze_info_acc (acc : info_acc) : info =
    {
      Stage_info.kernel_ir_nodes = List.rev acc.kernel_ir_nodes_rev;
      Stage_info.exported_node_summaries = List.rev acc.exported_node_summaries_rev;
      Stage_info.raw_ir_nodes = List.rev acc.raw_ir_nodes_rev;
      Stage_info.annotated_ir_nodes = List.rev acc.annotated_ir_nodes_rev;
      Stage_info.verified_ir_nodes = List.rev acc.verified_ir_nodes_rev;
      Stage_info.kernel_pipeline_lines = List.rev acc.kernel_pipeline_lines_rev;
      Stage_info.warnings = List.rev acc.warnings_rev;
      Stage_info.guarantee_automaton_lines = List.rev acc.guarantee_automaton_lines_rev;
      Stage_info.assume_automaton_lines = List.rev acc.assume_automaton_lines_rev;
      Stage_info.product_lines = List.rev acc.product_lines_rev;
      Stage_info.obligations_lines = List.rev acc.obligations_lines_rev;
      Stage_info.prune_lines = List.rev acc.prune_lines_rev;
      Stage_info.guarantee_automaton_dot = acc.guarantee_automaton_dot;
      Stage_info.assume_automaton_dot = acc.assume_automaton_dot;
      Stage_info.product_dot = acc.product_dot;
    }

  let instrument_node ~(program : ast_in) ~(automata : stage_in) (n : Abs.node) : Abs.node * info =
    match List.assoc_opt n.Abs.semantics.sem_nname automata with
    | Some build ->
        let info = Proof_obligation_pipeline.build_instrumentation_info ~build ~nodes:program n in
        (n, info)
    | None ->
        failwith
          (Printf.sprintf "Missing monitor generation build for node %s" n.Abs.semantics.sem_nname)

  let run_with_info (p : ast_in) (automata : stage_in) : ast_out * stage_out * info =
    let acc = empty_info_acc () in
    let ast =
      List.map
        (fun n ->
          let node, node_info = instrument_node ~program:p ~automata n in
          add_node_info acc node_info;
          node)
        p
    in
    let info = freeze_info_acc acc in
    (ast, automata, info)

  let run (p : ast_in) (automata : stage_in) : ast_out * stage_out =
    let ast, automata, _info = run_with_info p automata in
    (ast, automata)
end

module Pass :
  Pass_intf.S
    with type ast_in = Stage_types.contracts_stage
     and type ast_out = Stage_types.instrumentation_stage
     and type stage_in = Automata_generation.node_builds
     and type stage_out = Automata_generation.node_builds
     and type info = Stage_info.instrumentation_info = RawPass
