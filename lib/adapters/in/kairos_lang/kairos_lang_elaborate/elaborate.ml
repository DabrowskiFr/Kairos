(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 *---------------------------------------------------------------------------*)

open Core.Syntax
open Core.Ast

type source = {
  type_decls : enum_decl list;
  function_decls : pure_function_decl list;
  nodes : program;
}

(* Elaborate all declarations and nodes of a parsed source file. *)
let elaborate_source (source : Surface.Ast.source) : source =
  (* Validate and accumulate one frontend declaration. *)
  let elaborate_frontend_decl (env, type_decls, function_decls) = function
    | Surface.Ast.STypeDecl decl ->
        let env = Env.add_enum_decl env decl.enum_name decl.enum_constructors in
        (env, decl :: type_decls, function_decls)
    | Surface.Ast.SFunctionDecl f ->
        if List.mem_assoc f.function_name env.spec_defs then
          Shared.Error.elaboration
            (Printf.sprintf "pure function '%s' conflicts with a spec definition of the same name" f.function_name);
        let lowered = Lowering.lower_function_decl env f in
        let signature = (lowered.function_params, lowered.function_return) in
        let env = Env.add_function env lowered.function_name signature in
        (env, type_decls, lowered :: function_decls)
    | Surface.Ast.SSpecDefDecl d ->
        Validation.validate_spec_def_decl d;
        if List.mem_assoc d.spec_def_name env.functions then
          Shared.Error.elaboration
            (Printf.sprintf "spec definition '%s' conflicts with a pure function of the same name" d.spec_def_name);
        let env = Env.add_spec_def env d.spec_def_name d in
        (env, type_decls, function_decls)
  in
  let acc =
    List.fold_left elaborate_frontend_decl
      (Env.empty_env, [], [])
      source.frontend_decls
  in
  let env, type_decls, function_decls = acc in
  {
    type_decls = List.rev type_decls;
    function_decls = List.rev function_decls;
    nodes = List.map (Lowering.lower_node env) source.nodes;
  }
