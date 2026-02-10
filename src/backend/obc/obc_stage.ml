open Ast

let run_with_info (p:Ast.program) : Ast.program * Stage_info.obc_info =
  let ghost_locals = ref [] in
  let pre_k_infos = ref [] in
  let warnings = ref [] in
  let ast =
    List.map
      (fun n ->
         let node, info = Obc_ghost_instrument.transform_node_ghost_with_info n in
         ghost_locals := info.ghost_locals_added @ !ghost_locals;
         pre_k_infos := info.pre_k_infos @ !pre_k_infos;
         warnings := List.rev_append info.warnings !warnings;
         node)
      p
  in
  let info =
    {
      Stage_info.ghost_locals_added = List.rev !ghost_locals;
      Stage_info.pre_k_infos = List.rev !pre_k_infos;
      Stage_info.warnings = List.rev !warnings;
    }
  in
  (ast, info)

let run (p:Ast.program) : Ast.program =
  fst (run_with_info p)
