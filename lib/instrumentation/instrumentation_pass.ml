open Ast
open Support

module Abs = Abstract_model

module Pass = struct
  type ast_in = Stage_types.contracts_stage
  type ast_out = Stage_types.instrumentation_stage
  type stage_in = Automata_pass_sig.stage
  type stage_out = Automata_pass_sig.stage
  type info = Stage_info.instrumentation_info

  type info_acc = {
    mutable state_ctors_rev : ident list;
    mutable atom_count : int;
    mutable kernel_ir_nodes_rev : Product_kernel_ir.node_ir list;
    mutable exported_node_summaries_rev : Product_kernel_ir.exported_node_summary_ir list;
    mutable raw_ir_nodes_rev : Kairos_ir.raw_node list;
    mutable annotated_ir_nodes_rev : Kairos_ir.annotated_node list;
    mutable verified_ir_nodes_rev : Kairos_ir.verified_node list;
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
      state_ctors_rev = [];
      atom_count = 0;
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
    acc.state_ctors_rev <- node_info.state_ctors @ acc.state_ctors_rev;
    acc.atom_count <- acc.atom_count + node_info.atom_count;
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
      Stage_info.state_ctors = List.rev acc.state_ctors_rev;
      Stage_info.atom_count = acc.atom_count;
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

  let instrument_node ~(program : ast_in) ~(automata : stage_in)
      ~(external_summaries : Product_kernel_ir.exported_node_summary_ir list) (n : node) :
      node * info =
    match List.assoc_opt n.semantics.sem_nname automata with
    | Some build ->
        let n_abs = Abs.of_ast_node n in
        let all_nodes_abs = List.map Abs.of_ast_node program in
        let node_abs, info =
          Instrumentation.transform_abstract_node_with_info ~build ~nodes:all_nodes_abs
            ~external_summaries n_abs
        in
        (Abs.to_ast_node node_abs, info)
    | None ->
        failwith
          (Printf.sprintf "Missing monitor generation build for node %s" n.semantics.sem_nname)

  let run_with_external_summaries ~(external_summaries : Product_kernel_ir.exported_node_summary_ir list)
      (p : ast_in) (automata : stage_in) : ast_out * stage_out * info =
    let acc = empty_info_acc () in
    let ast =
      List.map
        (fun n ->
          let node, node_info = instrument_node ~program:p ~automata ~external_summaries n in
          add_node_info acc node_info;
          node)
        p
    in
    let info = freeze_info_acc acc in
    (ast, automata, info)

  let run_with_info (p : ast_in) (automata : stage_in) : ast_out * stage_out * info =
    run_with_external_summaries ~external_summaries:[] p automata

  let run (p : ast_in) (automata : stage_in) : ast_out * stage_out =
    let ast, automata, _info = run_with_info p automata in
    (ast, automata)
end

let run_with_info_external ?(external_summaries = []) (p : Pass.ast_in) (automata : Pass.stage_in) :
    Pass.ast_out * Pass.stage_out * Pass.info =
  Pass.run_with_external_summaries ~external_summaries p automata
