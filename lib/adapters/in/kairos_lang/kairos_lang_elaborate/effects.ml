(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 *---------------------------------------------------------------------------*)

(* Compute transitive read/write effects for executable methods. *)
open Core.Syntax

module StringSet = Set.Make (String)

(* Collect variable names read by an executable expression. *)
let rec ast_expr_refs acc (expr : Core.Syntax.expr) =
  match expr.expr with
  | ELitInt _ | ELitBool _ -> acc
  | EVar name -> StringSet.add name acc
  | EFunCall (_, args) -> List.fold_left ast_expr_refs acc args
  | EBin (_, left, right) | ECmp (_, left, right) ->
      ast_expr_refs (ast_expr_refs acc left) right
  | EUn (_, inner) -> ast_expr_refs acc inner

(* [direct_method_effects node_variables methods (reads, writes)] implements the internal direct method effects operation. It returns the operation result. *)
let rec direct_method_effects node_variables methods (reads, writes)
    (stmt : Core.Ast.stmt) =
  let add_expr reads expr = ast_expr_refs reads expr in
  let add_node_write writes name =
    if StringSet.mem name node_variables then StringSet.add name writes else writes
  in
  match stmt.stmt with
  | SAssign (name, rhs) ->
      (add_expr reads rhs, add_node_write writes name)
  | SAssert _ | SSkip -> (reads, writes)
  | SIf (guard, then_branch, else_branch) ->
      List.fold_left
        (direct_method_effects node_variables methods)
        (add_expr reads guard, writes) (then_branch @ else_branch)
  | SWhile (guard, _, variant, body) ->
      let reads = add_expr reads guard in
      let reads = Option.fold ~none:reads ~some:(add_expr reads) variant in
      List.fold_left (direct_method_effects node_variables methods)
        (reads, writes) body
  | SMatch (scrutinee, branches, default_branch) ->
      List.fold_left (direct_method_effects node_variables methods)
        (add_expr reads scrutinee, writes)
        (List.concat_map snd branches @ default_branch)
  | SMethodCall (callee, args) ->
      let reads = List.fold_left add_expr reads args in
      let writes =
        match List.assoc_opt callee methods with
        | None -> writes
        | Some (decl : Core.Ast.method_decl) ->
            List.fold_left2
              (fun writes (param : Core.Ast.method_param) arg ->
                match (param.method_param_mode, arg.expr) with
                | MPInOut, EVar name -> add_node_write writes name
                | _ -> writes)
              writes decl.method_params args
      in
      (reads, writes)

(* [infer_method_effects node_variables methods] computes the transitive sets
   of node variables read and written by each method. *)
let infer_method_effects node_variables methods =
  let lookup = List.map (fun (decl : Core.Ast.method_decl) -> (decl.method_name, decl)) methods in
  let direct =
    List.map
      (fun (decl : Core.Ast.method_decl) ->
        let reads, writes =
          List.fold_left (direct_method_effects node_variables lookup)
            (StringSet.empty, StringSet.empty) decl.method_body
        in
        (decl.method_name, (reads, writes)))
      methods
  in
  let rec calls_of_stmt acc (stmt : Core.Ast.stmt) =
    match stmt.stmt with
    | SMethodCall (name, _) -> StringSet.add name acc
    | SIf (_, left, right) -> List.fold_left calls_of_stmt acc (left @ right)
    | SWhile (_, _, _, body) -> List.fold_left calls_of_stmt acc body
    | SMatch (_, branches, default_branch) ->
        List.fold_left calls_of_stmt acc
          (List.concat_map snd branches @ default_branch)
    | SAssign _ | SAssert _ | SSkip -> acc
  in
  let calls =
    List.map
      (fun (decl : Core.Ast.method_decl) ->
        (decl.method_name,
         List.fold_left calls_of_stmt StringSet.empty decl.method_body))
      methods
  in
  let rec closure name seen =
    if StringSet.mem name seen then (StringSet.empty, StringSet.empty)
    else
      let seen = StringSet.add name seen in
      let reads, writes = List.assoc name direct in
      StringSet.fold
        (fun callee (reads, writes) ->
          let callee_reads, callee_writes = closure callee seen in
          (StringSet.union reads callee_reads, StringSet.union writes callee_writes))
        (List.assoc name calls) (reads, writes)
  in
  List.map
    (fun (decl : Core.Ast.method_decl) ->
      let reads, writes = closure decl.method_name StringSet.empty in
      {
        decl with
        method_reads = StringSet.elements (StringSet.inter reads node_variables);
        method_writes = StringSet.elements writes;
      })
    methods

(* [expand_observers_in_transition ~init_state schedule (t : S.transition)] transforms expand observers in transition. It returns the transformed representation. *)
