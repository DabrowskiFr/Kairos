(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frédéric Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *---------------------------------------------------------------------------*)

open Kr_lang_core.Kr_lang_core_syntax
open Env
open Core_conversion
open Type_checking
open History
open Effects
open Observer_pass
(* Internal module used by the elaboration pipeline. *)
module S = Kr_lang_surface.Kr_lang_surface_ast
module L = Kr_lang_surface.Kr_lang_surface_syntax
module B = Kr_lang_core.Kr_lang_core_syntax_builders

let is_scalar_ref_named = History.is_scalar_ref_named
let resolve_history_source_ref = History.resolve_history_source_ref
let infer_expr_type = Type_checking.infer_expr_type
let infer_hexpr_type = Type_checking.infer_hexpr_type
let check_expected_type = Type_checking.check_expected_type

let rec lower_expr env (e : L.expr) : expr =
  let expr =
    match e.sexpr with
    | SELitInt n -> ELitInt n
    | SELitBool b -> ELitBool b
    | SEVar r when r.ref_indices = [] -> (
        match Subst.nat_literal_of_ident r.ref_base with
        | Some n -> ELitInt n
        | None -> EVar (Names.indexed_ref_name r))
    | SEVar r -> EVar (Names.indexed_ref_name r)
    | SEPre r ->
        Kr_lang_shared.Kr_lang_shared_error.elaboration
          (Printf.sprintf
             "internal error: executable pre(%s) reached core lowering"
             (Names.indexed_ref_name r))
    | SECall (callee, args) -> (
        match function_sig env callee with
        | Some _ -> EFunCall (callee, List.map (lower_expr env) args)
        | None ->
            let args =
              List.map
                (fun (arg : L.expr) ->
                  L.mk_hexpr ?loc:arg.loc (SHExpr arg))
                args
            in
            (expr_of_fo
               (expand_predicate env empty_spec_context [] callee args))
              .expr)
    | SEBin (op, a, b) -> EBin (op, lower_expr env a, lower_expr env b)
    | SECmp (op, a, b) -> ECmp (op, lower_expr env a, lower_expr env b)
    | SEUn (op, inner) -> EUn (op, lower_expr env inner)
  in
  { expr; loc = e.loc }

and lower_hexpr ?(allow_old = false) env ctx stack (h : L.hexpr) : hexpr =
  let mk desc = B.mk_hexpr ?loc:h.hloc desc in
  match h.shexpr with
  | SHLitInt n -> mk (HLitInt n)
  | SHLitBool b -> mk (HLitBool b)
  | SHVar r -> (
      match scalar_nat_value ctx r with
      | Some n -> mk (HLitInt n)
      | None ->
          let r = ref_with_nat_params ctx r in
          begin
            match r with
            | { ref_base; _ } when is_scalar_ref_named ref_base r -> (
                match List.assoc_opt ref_base ctx.hexpr_params with
                | Some { shexpr = SHVar actual; _ } when is_scalar_ref_named ref_base actual ->
                    mk (HVar (Names.indexed_ref_name actual))
                | Some actual -> lower_hexpr ~allow_old env ctx stack actual
                | None -> mk (HVar (Names.indexed_ref_name r)))
            | _ -> mk (HVar (Names.indexed_ref_name r))
          end)
  | SHOld inner ->
      if not allow_old then
        Kr_lang_shared.Kr_lang_shared_error.elaboration
          "old is only allowed in method postconditions";
      mk (HOld (lower_hexpr ~allow_old env ctx stack inner))
  | SHPreK (r, k) -> (
      let k = eval_nat ctx k in
      let r = ref_with_nat_params ctx r in
      match r with
      | { ref_base; _ } when is_scalar_ref_named ref_base r -> (
          match List.assoc_opt ref_base ctx.hexpr_params with
          | Some { shexpr = SHVar actual; _ } when is_scalar_ref_named ref_base actual ->
              mk (HVar (Names.indexed_ref_name actual)) |> normalize_history_shift k
          | Some actual ->
              lower_hexpr ~allow_old env ctx stack actual |> normalize_history_shift k
          | None -> mk (HPreK (Names.indexed_ref_name r, k)))
      | _ -> mk (HPreK (Names.indexed_ref_name r, k)))
  | SHPast (inner, k) ->
      lower_hexpr ~allow_old env ctx stack inner
      |> normalize_history_shift (eval_nat ctx k)
  | SHHistoryAlias (alias, r) -> expand_history_alias env alias (Names.indexed_ref_name r)
  | SHCall (callee, args) -> (
      match function_sig env callee with
      | Some _ ->
        mk
          (HFunCall
             (callee, List.map (lower_hexpr ~allow_old env ctx stack) args))
      | None -> expand_predicate env ctx stack callee args)
  | SHExpr e -> B.hexpr_of_expr (lower_expr env e)
  | SHBin (op, a, b) ->
      mk
        (HBin
           (op, lower_hexpr ~allow_old env ctx stack a,
            lower_hexpr ~allow_old env ctx stack b))
  | SHCmp (op, a, b) ->
      mk
        (HCmp
           (op, lower_hexpr ~allow_old env ctx stack a,
            lower_hexpr ~allow_old env ctx stack b))
  | SHUn (op, inner) ->
      mk (HUn (op, lower_hexpr ~allow_old env ctx stack inner))
  | SHForall (param, enum_name, body) ->
      enum_members env enum_name
      |> List.map (fun value ->
             lower_hexpr ~allow_old env ctx stack
               (Subst.subst_hexpr ~param ~value body))
      |> core_hexpr_and
  | SHExists (param, enum_name, body) ->
      enum_members env enum_name
      |> List.map (fun value ->
             lower_hexpr ~allow_old env ctx stack
               (Subst.subst_hexpr ~param ~value body))
      |> core_hexpr_or
  | SHRangeForall (param, lo, hi, body) ->
      range_values (eval_nat ctx lo) (eval_nat ctx hi)
      |> List.map (fun value ->
             let ctx = { ctx with nat_params = (param, value) :: ctx.nat_params } in
             lower_hexpr ~allow_old env ctx stack body)
      |> core_hexpr_and
  | SHRangeExists (param, lo, hi, body) ->
      range_values (eval_nat ctx lo) (eval_nat ctx hi)
      |> List.map (fun value ->
             let ctx = { ctx with nat_params = (param, value) :: ctx.nat_params } in
             lower_hexpr ~allow_old env ctx stack body)
      |> core_hexpr_or

and expand_predicate env ctx stack name args =
  match List.assoc_opt name env.predicates with
  | None -> Kr_lang_shared.Kr_lang_shared_error.elaboration (Printf.sprintf "unknown predicate '%s'" name)
  | Some pred ->
      if List.mem name stack then
        Kr_lang_shared.Kr_lang_shared_error.elaboration (Printf.sprintf "cyclic predicate expansion involving '%s'" name);
      if List.length pred.predicate_params <> List.length args then
        Kr_lang_shared.Kr_lang_shared_error.elaboration
          (Printf.sprintf "predicate '%s' expects %d arguments but got %d" name
             (List.length pred.predicate_params) (List.length args));
      let actual_types =
        List.map
          (fun arg ->
            infer_hexpr_type env (lower_hexpr env ctx stack arg))
          args
      in
      List.iter2
        (fun (param : L.typed_param) actual_ty ->
          check_expected_type
            ~context:
              (Printf.sprintf "argument '%s' of predicate '%s'"
                 param.param_name name)
            param.param_ty actual_ty)
        pred.predicate_params actual_types;
      let fresh_params =
        List.mapi
          (fun index (param : L.typed_param) ->
            ( param,
              Names.generated_parameter_name "predicate_parameter" name
                index ))
          pred.predicate_params
      in
      let body =
        List.fold_left
          (fun body ((param : L.typed_param), fresh_name) ->
            Subst.subst_hexpr ~param:param.param_name ~value:fresh_name body)
          pred.predicate_body fresh_params
      in
      let ctx =
        List.fold_left2
          (fun ctx (_, fresh_name) value ->
            {
              ctx with
              hexpr_params =
                (fresh_name, value) :: ctx.hexpr_params;
            })
          ctx fresh_params args
      in
      let body = lower_hexpr env ctx (name :: stack) body in
      check_expected_type
        ~context:(Printf.sprintf "body of predicate '%s'" name)
        TBool (infer_hexpr_type env body);
      body

and bind_spec_param ctx (formal : L.spec_param) arg =
  match formal.spec_param_kind with
  | SPFormula ->
      { ctx with formula_params = (formal.spec_param_name, formula_arg_of_spec_arg ctx arg) :: ctx.formula_params }
  | SPHExpr ->
      { ctx with hexpr_params = (formal.spec_param_name, hexpr_arg_of_spec_arg ctx arg) :: ctx.hexpr_params }
  | SPNat ->
      { ctx with nat_params = (formal.spec_param_name, nat_arg_of_spec_arg ctx arg) :: ctx.nat_params }

and expand_spec_call env ctx name args =
  match List.assoc_opt name env.spec_defs with
  | Some def ->
      if List.mem name ctx.spec_stack then
        Kr_lang_shared.Kr_lang_shared_error.elaboration (Printf.sprintf "cyclic spec definition expansion involving '%s'" name);
      if List.length def.spec_def_params <> List.length args then
        Kr_lang_shared.Kr_lang_shared_error.elaboration
          (Printf.sprintf "spec definition '%s' expects %d arguments but got %d" name
             (List.length def.spec_def_params) (List.length args));
      let ctx =
        List.fold_left2 bind_spec_param
          { ctx with spec_stack = name :: ctx.spec_stack }
          def.spec_def_params args
      in
      lower_ltl env ctx def.spec_def_body
  | None ->
      let args = List.map (hexpr_arg_of_spec_arg ctx) args in
      (match function_sig env name with
      | Some _ ->
          let call =
            B.mk_hexpr
              (HFunCall
                 (name, List.map (lower_hexpr env ctx []) args))
          in
          check_expected_type
            ~context:(Printf.sprintf "temporal call to function '%s'" name)
            TBool (infer_hexpr_type env call);
          ltl_of_fo call
      | None -> ltl_of_fo (expand_predicate env ctx [] name args))

and lower_ltl env ctx (f : L.ltl) : ltl =
  match f with
  | SLTrue -> LTrue
  | SLFalse -> LFalse
  | SLAtom (a, op, b) -> LAtom (lower_hexpr env ctx [] a, op, lower_hexpr env ctx [] b)
  | SLFo h ->
      let h = lower_hexpr env ctx [] h in
      check_expected_type ~context:"temporal formula" TBool
        (infer_hexpr_type env h);
      ltl_of_fo h
  | SLFormulaParam name -> (
      match List.assoc_opt name ctx.formula_params with
      | Some f -> lower_ltl env ctx f
      | None -> Kr_lang_shared.Kr_lang_shared_error.elaboration (Printf.sprintf "unknown Formula parameter '%s'" name))
  | SLCall (name, args) -> expand_spec_call env ctx name args
  | SLNot inner -> LNot (lower_ltl env ctx inner)
  | SLAnd (a, b) -> LAnd (lower_ltl env ctx a, lower_ltl env ctx b)
  | SLOr (a, b) -> LOr (lower_ltl env ctx a, lower_ltl env ctx b)
  | SLImp (a, b) -> LImp (lower_ltl env ctx a, lower_ltl env ctx b)
  | SLX inner -> LX (lower_ltl env ctx inner)
  | SLG inner -> LG (lower_ltl env ctx inner)
  | SLW (a, b) -> LW (lower_ltl env ctx a, lower_ltl env ctx b)
  | SLForall (param, enum_name, body) ->
      enum_members env enum_name
      |> List.map (fun value -> lower_ltl env ctx (Subst.subst_ltl ~param ~value body))
      |> core_ltl_and
  | SLExists (param, enum_name, body) ->
      enum_members env enum_name
      |> List.map (fun value -> lower_ltl env ctx (Subst.subst_ltl ~param ~value body))
      |> core_ltl_or
  | SLRangeForall (param, lo, hi, body) ->
      range_values (eval_nat ctx lo) (eval_nat ctx hi)
      |> List.map (fun value ->
             let ctx = { ctx with nat_params = (param, value) :: ctx.nat_params } in
             lower_ltl env ctx body)
      |> core_ltl_and
  | SLRangeExists (param, lo, hi, body) ->
      range_values (eval_nat ctx lo) (eval_nat ctx hi)
      |> List.map (fun value ->
             let ctx = { ctx with nat_params = (param, value) :: ctx.nat_params } in
             lower_ltl env ctx body)
      |> core_ltl_or

let rec lower_contract_ltls env (f : L.ltl) : ltl list =
  match f with
  | SLAnd (a, b) -> lower_contract_ltls env a @ lower_contract_ltls env b
  | SLForall (param, enum_name, body) ->
      enum_members env enum_name
      |> List.concat_map (fun value -> lower_contract_ltls env (Subst.subst_ltl ~param ~value body))
  | SLRangeForall (param, lo, hi, body) ->
      range_values (eval_nat empty_spec_context lo) (eval_nat empty_spec_context hi)
      |> List.concat_map (fun value ->
             let ctx = { empty_spec_context with nat_params = [ (param, value) ] } in
             [ lower_ltl env ctx body ])
  | _ -> [ lower_ltl env empty_spec_context f ]


(* Lower one pure function and its first-order contracts. *)
let lower_function_decl env (f : S.function_decl) : pure_function_decl =
  {
    function_name = f.function_name;
    function_params = lower_raw_vdecls env f.function_params;
    function_return = f.function_return;
    function_requires = List.map (lower_hexpr env empty_spec_context []) f.function_requires;
    function_ensures = List.map (lower_hexpr env empty_spec_context []) f.function_ensures;
    function_body = lower_expr env f.function_body;
  }

(* [validate_stmt_match env scrutinee branches default_branch] checks that an
   enum match is type-correct, has no duplicate branches, and is exhaustive;
   it raises an elaboration error on an invalid branch layout. *)
let validate_stmt_match env scrutinee branches default_branch =
  let scrutinee_ty = infer_expr_type env (lower_expr env scrutinee) in
  let enum_name, constructors =
    match scrutinee_ty with
    | TCustom enum_name when List.mem_assoc enum_name env.enum_sets ->
        (enum_name, enum_members env enum_name)
    | ty ->
        Kr_lang_shared.Kr_lang_shared_error.elaboration
          (Printf.sprintf "match scrutinee must have an enum type, but has type '%s'"
             (type_name ty))
  in
  let constructor_enum ctor =
    List.find_map
      (fun (name, members) -> if List.mem ctor members then Some name else None)
      env.enum_sets
  in
  let seen = Hashtbl.create (List.length branches) in
  List.iter
    (fun (ctor, _) ->
      match constructor_enum ctor with
      | None ->
          Kr_lang_shared.Kr_lang_shared_error.elaboration
            (Printf.sprintf "unknown constructor '%s' in match on enum '%s'" ctor
               enum_name)
      | Some actual_enum when not (String.equal actual_enum enum_name) ->
          Kr_lang_shared.Kr_lang_shared_error.elaboration
            (Printf.sprintf
               "constructor '%s' belongs to enum '%s', not matched enum '%s'" ctor
               actual_enum enum_name)
      | Some _ ->
          if Hashtbl.mem seen ctor then
            Kr_lang_shared.Kr_lang_shared_error.well_formedness
              (Printf.sprintf "duplicate match branch for constructor '%s'" ctor);
          Hashtbl.add seen ctor ())
    branches;
  let missing = List.filter (fun ctor -> not (Hashtbl.mem seen ctor)) constructors in
  match (missing, default_branch) with
  | [], Some _ ->
      Kr_lang_shared.Kr_lang_shared_error.well_formedness
        "match '_' branch is unreachable because all constructors are covered"
  | _ :: _, None ->
      Kr_lang_shared.Kr_lang_shared_error.well_formedness
        (Printf.sprintf "non-exhaustive match on enum '%s'; missing: %s" enum_name
           (String.concat ", " missing))
  | [], None | _ :: _, Some _ -> ()

(* [lower_stmt env stack s] lowers one surface statement to core statements,
   expanding finite loops and resolving method calls in the supplied context. *)
let rec lower_stmt env stack (s : S.stmt) : Kr_lang_core.Kr_lang_core_ast.stmt list =
  match s.sstmt with
  | SSAssign (lhs, rhs) ->
      [ Kr_lang_core.Kr_lang_core_ast_builders.mk_stmt ?loc:s.sloc (SAssign (Names.indexed_ref_name lhs, lower_expr env rhs)) ]
  | SSIf (cond, then_branch, else_branch) ->
      [
        Kr_lang_core.Kr_lang_core_ast_builders.mk_stmt ?loc:s.sloc
          (SIf
             ( lower_expr env cond,
               lower_stmt_list env stack then_branch,
               lower_stmt_list env stack else_branch ));
      ]
  | SSWhile (cond, invariants, variant, body) ->
      [
        Kr_lang_core.Kr_lang_core_ast_builders.mk_stmt ?loc:s.sloc
          (SWhile
             ( lower_expr env cond,
               List.map (lower_hexpr env empty_spec_context []) invariants,
               Option.map (lower_expr env) variant,
               lower_stmt_list env stack body ));
      ]
  | SSMatch (scrutinee, branches, default_branch) ->
      validate_stmt_match env scrutinee branches default_branch;
      let lowered_default =
        match default_branch with
        | None -> []
        | Some [] -> [ Kr_lang_core.Kr_lang_core_ast_builders.mk_stmt ?loc:s.sloc SSkip ]
        | Some body -> lower_stmt_list env stack body
      in
      [
        Kr_lang_core.Kr_lang_core_ast_builders.mk_stmt ?loc:s.sloc
          (SMatch
               ( lower_expr env scrutinee,
               List.map (fun (ctor, body) -> (ctor, lower_stmt_list env stack body)) branches,
               lowered_default ));
      ]
  | SSSkip -> [ Kr_lang_core.Kr_lang_core_ast_builders.mk_stmt ?loc:s.sloc SSkip ]
  | SSMethodCall (callee, args) ->
      let method_decl =
        match List.assoc_opt callee env.methods with
        | Some method_decl -> method_decl
        | None ->
            Kr_lang_shared.Kr_lang_shared_error.elaboration
              (Printf.sprintf "unknown method '%s'" callee)
      in
      if List.length method_decl.method_params <> List.length args then
        Kr_lang_shared.Kr_lang_shared_error.elaboration
          (Printf.sprintf "method '%s' expects %d arguments but got %d" callee
             (List.length method_decl.method_params) (List.length args));
      List.iter2
        (fun (param : S.method_param) (arg : S.expr) ->
          let actual_ty = infer_expr_type env (lower_expr env arg) in
          check_expected_type
            ~context:
              (Printf.sprintf "argument '%s' of method '%s'"
                 param.method_param_name callee)
            param.method_param_ty actual_ty;
          match (param.method_param_mode, arg.sexpr) with
          | MPIn, _ -> ()
          | MPInOut, SEVar target
            when List.mem_assoc (Names.indexed_ref_name target) env.variables ->
              ()
          | MPInOut, SEVar target ->
              Kr_lang_shared.Kr_lang_shared_error.elaboration
                (Printf.sprintf
                   "inout parameter '%s' of method '%s' requires a writable variable, but '%s' is not a node variable"
                   param.method_param_name callee (Names.indexed_ref_name target))
          | MPInOut, _ ->
              Kr_lang_shared.Kr_lang_shared_error.elaboration
                (Printf.sprintf
                   "inout parameter '%s' of method '%s' requires a variable reference argument"
                   param.method_param_name callee))
        method_decl.method_params args;
      [
        Kr_lang_core.Kr_lang_core_ast_builders.mk_stmt ?loc:s.sloc
          (SMethodCall (callee, List.map (lower_expr env) args));
      ]
  | SSFor (param, enum_name, body) ->
      enum_members env enum_name
      |> List.concat_map (fun value ->
             body
             |> List.map (Subst.subst_stmt ~param ~value)
             |> lower_stmt_list env stack)
  | SSForRange (param, lo, hi, body) ->
      range_values (eval_nat empty_spec_context lo) (eval_nat empty_spec_context hi)
      |> List.concat_map (fun value ->
             body
             |> List.map (Subst.subst_stmt ~param ~value:(string_of_int value))
             |> lower_stmt_list env stack)

and lower_stmt_list env stack stmts =
  List.concat_map (lower_stmt env stack) stmts

(* [method_env env (decl : S.method_decl)] implements the internal method env operation. It returns the operation result. *)
let method_env env (decl : S.method_decl) =
  let parameters =
    List.map
      (fun (param : S.method_param) ->
        (param.method_param_name, param.method_param_ty))
      decl.method_params
  in
  { env with variables = parameters @ env.variables }

(* [lower_method ~node_inputs env decl] lowers a method declaration, including
   its contracts and inferred effects, to the core representation. *)
let lower_method ~node_inputs env (decl : S.method_decl) : Kr_lang_core.Kr_lang_core_ast.method_decl =
  let method_env = method_env env decl in
  let lowered =
    {
    Kr_lang_core.Kr_lang_core_ast.method_name = decl.method_name;
    method_params = decl.method_params;
    method_requires =
      List.map
        (lower_hexpr method_env empty_spec_context [])
        decl.method_requires;
    method_ensures =
      List.map
        (lower_hexpr ~allow_old:true method_env empty_spec_context [])
        decl.method_ensures;
    method_body = lower_stmt_list method_env [] decl.method_body;
    method_reads = [];
    method_writes = [];
    }
  in
  let read_only =
    List.filter
      (fun name ->
        not
          (List.exists
             (fun (param : S.method_param) ->
               String.equal param.method_param_name name)
             decl.method_params))
      node_inputs
    @ List.filter_map
        (fun (param : S.method_param) ->
          match param.method_param_mode with
          | MPIn -> Some param.method_param_name
          | MPInOut -> None)
        decl.method_params
  in
  let type_of_target name =
    match List.assoc_opt name method_env.variables with
    | Some ty -> ty
    | None ->
        Kr_lang_shared.Kr_lang_shared_error.elaboration
          (Printf.sprintf "unknown assignment target '%s' in method '%s'" name
             decl.method_name)
  in
  let rec validate_stmt (stmt : Kr_lang_core.Kr_lang_core_ast.stmt) =
    match stmt.stmt with
    | SAssign (name, rhs) ->
        if List.mem name read_only then
          Kr_lang_shared.Kr_lang_shared_error.well_formedness
            (Printf.sprintf
               "method '%s' cannot assign read-only variable '%s'"
               decl.method_name name);
        check_expected_type
          ~context:(Printf.sprintf "assignment to '%s' in method '%s'" name decl.method_name)
          (type_of_target name) (infer_expr_type method_env rhs)
    | SAssert formula ->
        check_expected_type
          ~context:(Printf.sprintf "assertion in method '%s'" decl.method_name)
          TBool (infer_hexpr_type method_env formula)
    | SIf (condition, left, right) ->
        check_expected_type
          ~context:(Printf.sprintf "if condition in method '%s'" decl.method_name)
          TBool (infer_expr_type method_env condition);
        List.iter validate_stmt (left @ right)
    | SWhile (condition, invariants, variant, body) ->
        check_expected_type
          ~context:(Printf.sprintf "while condition in method '%s'" decl.method_name)
          TBool (infer_expr_type method_env condition);
        List.iter
          (fun invariant ->
            check_expected_type
              ~context:(Printf.sprintf "while invariant in method '%s'" decl.method_name)
              TBool (infer_hexpr_type method_env invariant))
          invariants;
        Option.iter
          (fun term ->
            check_expected_type
              ~context:(Printf.sprintf "while variant in method '%s'" decl.method_name)
              TInt (infer_expr_type method_env term))
          variant;
        List.iter validate_stmt body
    | SMatch (_, branches, default_branch) ->
        List.iter validate_stmt
          (List.concat_map snd branches @ default_branch)
    | SMethodCall _ | SSkip -> ()
  in
  List.iter
    (fun formula ->
      check_expected_type
        ~context:(Printf.sprintf "requires clause of method '%s'" decl.method_name)
        TBool (infer_hexpr_type method_env formula))
    lowered.method_requires;
  List.iter
    (fun formula ->
      check_expected_type
        ~context:(Printf.sprintf "ensures clause of method '%s'" decl.method_name)
        TBool (infer_hexpr_type method_env formula))
    lowered.method_ensures;
  List.iter validate_stmt lowered.method_body;
  lowered

(* Internal module used by the elaboration pipeline. *)
let lower_contracts ~hide_init env contracts =
  let assumes, guarantees =
    List.fold_left
      (fun (assumes, guarantees) -> function
        | S.SCAssume (_, f) ->
            (List.rev_append (lower_contract_ltls env f) assumes, guarantees)
        | S.SCGuarantee (_, f) ->
            let f = if hide_init then S.SLX f else f in
            (assumes, List.rev_append (lower_contract_ltls env f) guarantees))
      ([], []) contracts
  in
  (List.rev assumes, List.rev guarantees)

(* [lower_transition env (t : S.transition) : Kr_lang_core.Kr_lang_core_ast.transition] transforms lower transition. It returns the transformed representation. *)
let lower_transition env (t : S.transition) : Kr_lang_core.Kr_lang_core_ast.transition =
  Kr_lang_core.Kr_lang_core_ast_builders.mk_transition ~src:t.src ~dst:t.dst
    ~guard:(Option.map (lower_expr env) t.guard)
    ~body:(lower_stmt_list env [] t.body)
    ~ensures:(List.map (lower_hexpr env empty_spec_context []) t.ensures)
    ()

(* [node_env base_env (n : S.node)] implements the internal node env operation. It returns the operation result. *)
let node_env base_env (n : S.node) =
  Validation.validate_unique_named_decls "predicate" (fun (p : S.predicate_decl) -> p.predicate_name) n.predicates;
  Validation.validate_unique_named_decls "method" (fun (a : S.method_decl) -> a.method_name) n.methods;
  Validation.validate_unique_named_decls "history alias" (fun (a : S.history_alias_decl) -> a.alias_name) n.history_aliases;
  List.iter
    (fun (p : S.predicate_decl) ->
      if List.mem_assoc p.predicate_name base_env.functions then
        Kr_lang_shared.Kr_lang_shared_error.elaboration
          (Printf.sprintf "predicate '%s' conflicts with a pure function of the same name" p.predicate_name))
    n.predicates;
  List.iter
    (fun (p : S.predicate_decl) ->
      if List.mem_assoc p.predicate_name base_env.spec_defs then
        Kr_lang_shared.Kr_lang_shared_error.elaboration
          (Printf.sprintf "predicate '%s' conflicts with a spec definition of the same name" p.predicate_name))
    n.predicates;
  List.iter
    (fun (a : S.method_decl) ->
      if List.mem_assoc a.method_name base_env.functions then
        Kr_lang_shared.Kr_lang_shared_error.elaboration
          (Printf.sprintf "method '%s' conflicts with a pure function of the same name" a.method_name))
    n.methods;
  List.iter
    (fun (a : S.method_decl) ->
      if List.mem_assoc a.method_name base_env.spec_defs then
        Kr_lang_shared.Kr_lang_shared_error.elaboration
          (Printf.sprintf "method '%s' conflicts with a spec definition of the same name" a.method_name))
    n.methods;
  List.iter
    (fun (a : S.method_decl) ->
      if List.exists (fun (p : S.predicate_decl) -> String.equal p.predicate_name a.method_name) n.predicates then
        Kr_lang_shared.Kr_lang_shared_error.elaboration
          (Printf.sprintf "method '%s' conflicts with a predicate of the same name" a.method_name))
    n.methods;
  let variable_decls =
    lower_raw_vdecls base_env
      (n.inputs @ n.outputs @ n.locals @ n.ghosts)
    @ List.map
        (fun (observer : S.observer_decl) ->
          {
            vname = observer.observer_name;
            vty = observer.observer_ty;
          })
        n.observers
  in
  let variables =
    List.map (fun (decl : vdecl) -> (decl.vname, decl.vty)) variable_decls
  in
  List.iter
    (fun (predicate : S.predicate_decl) ->
      Validation.validate_unique_named_decls "predicate parameter"
        (fun (param : S.typed_param) -> param.param_name)
        predicate.predicate_params;
      List.iter
        (fun (param : S.typed_param) ->
          validate_type base_env
            (Printf.sprintf "parameter '%s' of predicate '%s'"
               param.param_name predicate.predicate_name)
            param.param_ty)
        predicate.predicate_params)
    n.predicates;
  List.iter
    (fun (method_decl : S.method_decl) ->
      List.iter
        (fun (param : S.method_param) ->
          validate_type base_env
            (Printf.sprintf "parameter '%s' of method '%s'"
               param.method_param_name method_decl.method_name)
            param.method_param_ty)
        method_decl.method_params)
    n.methods;
  {
    base_env with
    variables;
    predicates = List.map (fun p -> (p.S.predicate_name, p)) n.predicates;
    methods = List.map (fun a -> (a.S.method_name, a)) n.methods;
    history_aliases =
      List.map
        (fun a ->
          if a.S.alias_k < 1 then
            Kr_lang_shared.Kr_lang_shared_error.elaboration
              (Printf.sprintf "history alias '%s' uses invalid k=%d (expected >= 1)" a.alias_name a.alias_k);
          if not (String.equal a.alias_param a.alias_rhs_param) then
            Kr_lang_shared.Kr_lang_shared_error.elaboration
              (Printf.sprintf
                 "history alias '%s' is inconsistent: parameter is '%s' but rhs uses '%s'"
                 a.alias_name a.alias_param a.alias_rhs_param);
          (a.alias_name, (a.alias_param, a.alias_k)))
        n.history_aliases;
  }

(* [lower_node base_env n] validates and lowers one surface node, adding
   observer state, contracts, delays, and inferred method effects. *)
let lower_node base_env (n : S.node) : Kr_lang_core.Kr_lang_core_ast.node =
  Validation.validate_control_graph n;
  let env = node_env base_env n in
  Validation.validate_observers n;
  Validation.validate_method_contracts n;
  Validation.validate_method_parameters n;
  Validation.validate_method_call_graph n;
  Validation.validate_while_variants n;
  let contracts = n.contracts in
  let generated_observer_ghosts = Observers.observer_locals n.observers in
  let preliminary_generated_variables =
    lower_raw_vdecls env
      generated_observer_ghosts
    |> List.map (fun (decl : vdecl) -> (decl.vname, decl.vty))
  in
  let preliminary_env =
    { env with variables = preliminary_generated_variables @ env.variables }
  in
  let delays = Delays.collect preliminary_env n.observers in
  let generated_delay_ghosts = Delays.ghosts delays in
  let observers = Delays.rewrite_observers delays n.observers in
  let observer_schedule = Observers.schedule ~predicates:n.predicates observers in
  let generated_variables =
    lower_raw_vdecls preliminary_env generated_delay_ghosts
    |> List.map (fun (decl : vdecl) -> (decl.vname, decl.vty))
  in
  let env =
    { preliminary_env with variables = generated_variables @ preliminary_env.variables }
  in
  let public_ghosts = List.map (fun (o : S.observer_decl) -> o.observer_name) n.observers in
  let transitions =
    complete_observer_transitions n
    |> List.map
         (expand_observers_in_transition ~init_state:n.state_decls.init_state observer_schedule)
    |> List.map (Delays.append_commits delays)
  in
  let assumes, guarantees =
    lower_contracts ~hide_init:n.state_decls.init_is_hidden env contracts
  in
  let state_invariants =
    State_selectors.expand_state_invariants n
    @ Delays.state_invariants ~states:n.state_decls.states
        ~init_state:n.state_decls.init_state delays
  in
  let node_variables =
    List.fold_left
      (fun names (name, _) -> StringSet.add name names)
      StringSet.empty env.variables
  in
  let methods =
    let node_inputs =
      lower_raw_vdecls env n.inputs |> List.map (fun (decl : vdecl) -> decl.vname)
    in
    List.map (lower_method ~node_inputs env) n.methods
    |> infer_method_effects node_variables
  in
  let node =
    Kr_lang_core.Kr_lang_core_ast_builders.mk_node ~nname:n.node_name ~inputs:(lower_raw_vdecls env n.inputs)
	  ~outputs:(lower_raw_vdecls env n.outputs) ~assumes ~guarantees
	  ~locals:(lower_raw_vdecls env n.locals)
	  ~ghosts:(lower_raw_vdecls env
        (n.ghosts @ generated_observer_ghosts
       @ generated_delay_ghosts))
	  ~public_ghosts
      ~methods
      ~states:n.state_decls.states ~init_state:n.state_decls.init_state
      ~trans:(List.map (lower_transition env) transitions)
  in
  {
    node with
    specification =
      {
        node.specification with
        spec_invariants_state_rel =
          List.map
            (fun (state, formula) ->
              { Kr_lang_core.Kr_lang_core_ast.state; formula = lower_hexpr env empty_spec_context [] formula })
            state_invariants;
      };
  }
