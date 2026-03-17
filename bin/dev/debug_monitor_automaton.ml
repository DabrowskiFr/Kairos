open Ast

let () =
  if Array.length Sys.argv < 2 then (
    prerr_endline "usage: debug_monitor_automaton <file.kairos>";
    exit 2);
  let file = Sys.argv.(1) in
  let source = Parse_file.parse_source_file file in
  List.iter
    (fun (n : Ast.node) ->
      let spec = Ast.specification_of_node n in
      let build = Automata_generation.build_for_node n in
      let abs_node = Abstract_model.of_ast_node n in
      let analysis = Product_build.analyze_node ~build ~node:abs_node in
      let spot_formula =
        Spot_automaton.string_of_spot_ltl ~atom_map:build.atoms.atom_map build.spec
      in
      Printf.printf "NODE %s\n" n.nname;
      List.iteri
        (fun i g -> Printf.printf "GUARANTEE[%d] %s\n" i (Support.string_of_ltl g))
        spec.spec_guarantees;
      List.iteri
        (fun i (fo, name) ->
          Printf.printf "ATOM[%d] %s := %s\n" i name (Support.string_of_fo fo))
        build.atoms.atom_map;
      Printf.printf "SPOT %s\n" spot_formula;
      List.iter
        (fun (src, guard, dst) ->
          let raw_guard_fo = Automata_atoms.recover_guard_fo build.atoms.atom_name_to_fo guard in
          let simplified_guard_fo = Fo_simplifier.simplify_fo raw_guard_fo in
          Printf.printf "EDGE %d -> %d RAW %s\n" src dst (Support.string_of_fo raw_guard_fo);
          Printf.printf "EDGE %d -> %d SIMPL %s\n" src dst (Support.string_of_fo simplified_guard_fo))
        build.automaton.grouped;
      List.iter
        (fun (src, guard, dst) ->
          let raw_guard_fo =
            Automata_atoms.recover_guard_fo analysis.guarantee_atom_name_to_fo guard
          in
          Printf.printf "ANALYSIS EDGE %d -> %d RAW %s\n" src dst (Support.string_of_fo raw_guard_fo))
        analysis.guarantee_grouped_edges;
      Printf.printf "ANALYSIS EDGE COUNT %d\n" (List.length analysis.guarantee_grouped_edges);
      print_endline "")
    source.Source_file.nodes
