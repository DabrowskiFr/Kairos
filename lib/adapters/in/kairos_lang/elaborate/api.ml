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

open Surface.Ast
open Core.Syntax

module S = Surface.Ast
module Names = Names
module Delays = Delays
module Observers = Observers
module State_selectors = State_selectors
module Subst = Subst
module Validation = Validation
include Env
include Logic

type source = {
  type_decls : enum_decl list;
  function_decls : pure_function_decl list;
  nodes : Core.Ast.program;
}

let indexed_ref_name = Names.indexed_ref_name

let subst_stmt = Subst.subst_stmt

let validate_stmt_match env scrutinee branches default_branch =
  let scrutinee_ty = infer_expr_type env (lower_expr env scrutinee) in
  let enum_name, constructors =
    match scrutinee_ty with
    | TCustom enum_name when List.mem_assoc enum_name env.enum_sets ->
        (enum_name, enum_members env enum_name)
    | ty ->
        Shared.Error.elaboration
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
          Shared.Error.elaboration
            (Printf.sprintf "unknown constructor '%s' in match on enum '%s'" ctor
               enum_name)
      | Some actual_enum when not (String.equal actual_enum enum_name) ->
          Shared.Error.elaboration
            (Printf.sprintf
               "constructor '%s' belongs to enum '%s', not matched enum '%s'" ctor
               actual_enum enum_name)
      | Some _ ->
          if Hashtbl.mem seen ctor then
            Shared.Error.well_formedness
              (Printf.sprintf "duplicate match branch for constructor '%s'" ctor);
          Hashtbl.add seen ctor ())
    branches;
  let missing = List.filter (fun ctor -> not (Hashtbl.mem seen ctor)) constructors in
  match (missing, default_branch) with
  | [], Some _ ->
      Shared.Error.well_formedness
        "match '_' branch is unreachable because all constructors are covered"
  | _ :: _, None ->
      Shared.Error.well_formedness
        (Printf.sprintf "non-exhaustive match on enum '%s'; missing: %s" enum_name
           (String.concat ", " missing))
  | [], None | _ :: _, Some _ -> ()

let rec lower_stmt env stack (s : S.stmt) : Core.Ast.stmt list =
  match s.sstmt with
  | SSAssign (lhs, rhs) ->
      [ Core.Ast_builders.mk_stmt ?loc:s.sloc (SAssign (indexed_ref_name lhs, lower_expr env rhs)) ]
  | SSIf (cond, then_branch, else_branch) ->
      [
        Core.Ast_builders.mk_stmt ?loc:s.sloc
          (SIf
             ( lower_expr env cond,
               lower_stmt_list env stack then_branch,
               lower_stmt_list env stack else_branch ));
      ]
  | SSWhile (cond, invariants, variant, body) ->
      [
        Core.Ast_builders.mk_stmt ?loc:s.sloc
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
        | Some [] -> [ Core.Ast_builders.mk_stmt ?loc:s.sloc SSkip ]
        | Some body -> lower_stmt_list env stack body
      in
      [
        Core.Ast_builders.mk_stmt ?loc:s.sloc
          (SMatch
               ( lower_expr env scrutinee,
               List.map (fun (ctor, body) -> (ctor, lower_stmt_list env stack body)) branches,
               lowered_default ));
      ]
  | SSSkip -> [ Core.Ast_builders.mk_stmt ?loc:s.sloc SSkip ]
  | SSMethodCall (callee, args) ->
      let method_decl =
        match List.assoc_opt callee env.methods with
        | Some method_decl -> method_decl
        | None ->
            Shared.Error.elaboration
              (Printf.sprintf "unknown method '%s'" callee)
      in
      if List.length method_decl.method_params <> List.length args then
        Shared.Error.elaboration
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
            when List.mem_assoc (indexed_ref_name target) env.variables ->
              ()
          | MPInOut, SEVar target ->
              Shared.Error.elaboration
                (Printf.sprintf
                   "inout parameter '%s' of method '%s' requires a writable variable, but '%s' is not a node variable"
                   param.method_param_name callee (indexed_ref_name target))
          | MPInOut, _ ->
              Shared.Error.elaboration
                (Printf.sprintf
                   "inout parameter '%s' of method '%s' requires a variable reference argument"
                   param.method_param_name callee))
        method_decl.method_params args;
      [
        Core.Ast_builders.mk_stmt ?loc:s.sloc
          (SMethodCall (callee, List.map (lower_expr env) args));
      ]
  | SSFor (param, enum_name, body) ->
      enum_members env enum_name
      |> List.concat_map (fun value ->
             body
             |> List.map (subst_stmt ~param ~value)
             |> lower_stmt_list env stack)
  | SSForRange (param, lo, hi, body) ->
      range_values (eval_nat empty_spec_context lo) (eval_nat empty_spec_context hi)
      |> List.concat_map (fun value ->
             body
             |> List.map (subst_stmt ~param ~value:(string_of_int value))
             |> lower_stmt_list env stack)

and lower_stmt_list env stack stmts =
  List.concat_map (lower_stmt env stack) stmts

let method_env env (decl : S.method_decl) =
  let parameters =
    List.map
      (fun (param : S.method_param) ->
        (param.method_param_name, param.method_param_ty))
      decl.method_params
  in
  { env with variables = parameters @ env.variables }

let lower_method ~node_inputs env (decl : S.method_decl) : Core.Ast.method_decl =
  let method_env = method_env env decl in
  let lowered =
    {
    Core.Ast.method_name = decl.method_name;
    method_params =
      List.map
        (fun (param : S.method_param) ->
          {
            Core.Ast.method_param_name = param.method_param_name;
            method_param_ty = param.method_param_ty;
            method_param_mode =
              (match param.method_param_mode with MPIn -> Core.Ast.MPIn | MPInOut -> MPInOut);
          })
        decl.method_params;
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
        Shared.Error.elaboration
          (Printf.sprintf "unknown assignment target '%s' in method '%s'" name
             decl.method_name)
  in
  let rec validate_stmt (stmt : Core.Ast.stmt) =
    match stmt.stmt with
    | SAssign (name, rhs) ->
        if List.mem name read_only then
          Shared.Error.well_formedness
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

module StringSet = Set.Make (String)

let rec ast_expr_refs acc (expr : Core.Syntax.expr) =
  match expr.expr with
  | ELitInt _ | ELitBool _ -> acc
  | EVar name -> StringSet.add name acc
  | EFunCall (_, args) -> List.fold_left ast_expr_refs acc args
  | EBin (_, left, right) | ECmp (_, left, right) ->
      ast_expr_refs (ast_expr_refs acc left) right
  | EUn (_, inner) -> ast_expr_refs acc inner

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

let validate_unique_named_decls = Validation.validate_unique_named_decls
let validate_control_graph = Validation.validate_control_graph
let validate_observers = Validation.validate_observers
let validate_method_contracts = Validation.validate_method_contracts
let validate_method_parameters = Validation.validate_method_parameters
let validate_method_call_graph = Validation.validate_method_call_graph
let validate_while_variants = Validation.validate_while_variants
let validate_spec_def_decl = Validation.validate_spec_def_decl
let observer_updates_for_transition = Observers.observer_updates_for_transition
let observer_locals = Observers.observer_locals
let expand_state_invariants = State_selectors.expand_state_invariants

let expand_observers_in_transition ~init_state schedule (t : S.transition) =
  { t with body = t.body @ observer_updates_for_transition ~init_state schedule t }

let is_catch_all_transition_from state (transition : S.transition) =
  String.equal transition.src state
  &&
  match transition.guard with
  | None -> true
  | Some { sexpr = SELitBool true; _ } -> true
  | Some _ -> false

let complete_observer_transitions (n : S.node) =
  if n.observers = [] then n.transitions
  else
    let states_without_catch_all =
      n.state_decls.states
      |> List.filter (fun state ->
             not (List.exists (is_catch_all_transition_from state) n.transitions))
    in
    if List.mem n.state_decls.init_state states_without_catch_all then
      Shared.Error.well_formedness
        (Printf.sprintf
           "observer initialization in node '%s' requires a catch-all transition from initial state '%s'; an implicit fallback would return to the initial state"
           n.node_name n.state_decls.init_state);
    let fallbacks =
      states_without_catch_all
      |> List.map (fun state : S.transition ->
             {
               src = state;
               dst = state;
               guard = None;
               body = [];
               ensures = [];
             })
    in
    n.transitions @ fallbacks

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

let lower_transition env (t : S.transition) : Core.Ast.transition =
  Core.Ast_builders.mk_transition ~src:t.src ~dst:t.dst
    ~guard:(Option.map (lower_expr env) t.guard)
    ~body:(lower_stmt_list env [] t.body)
    ~ensures:(List.map (lower_hexpr env empty_spec_context []) t.ensures)
    ()

let node_env base_env (n : S.node) =
  validate_unique_named_decls "predicate" (fun (p : S.predicate_decl) -> p.predicate_name) n.predicates;
  validate_unique_named_decls "method" (fun (a : S.method_decl) -> a.method_name) n.methods;
  validate_unique_named_decls "history alias" (fun (a : S.history_alias_decl) -> a.alias_name) n.history_aliases;
  List.iter
    (fun (p : S.predicate_decl) ->
      if List.mem_assoc p.predicate_name base_env.functions then
        Shared.Error.elaboration
          (Printf.sprintf "predicate '%s' conflicts with a pure function of the same name" p.predicate_name))
    n.predicates;
  List.iter
    (fun (p : S.predicate_decl) ->
      if List.mem_assoc p.predicate_name base_env.spec_defs then
        Shared.Error.elaboration
          (Printf.sprintf "predicate '%s' conflicts with a spec definition of the same name" p.predicate_name))
    n.predicates;
  List.iter
    (fun (a : S.method_decl) ->
      if List.mem_assoc a.method_name base_env.functions then
        Shared.Error.elaboration
          (Printf.sprintf "method '%s' conflicts with a pure function of the same name" a.method_name))
    n.methods;
  List.iter
    (fun (a : S.method_decl) ->
      if List.mem_assoc a.method_name base_env.spec_defs then
        Shared.Error.elaboration
          (Printf.sprintf "method '%s' conflicts with a spec definition of the same name" a.method_name))
    n.methods;
  List.iter
    (fun (a : S.method_decl) ->
      if List.exists (fun (p : S.predicate_decl) -> String.equal p.predicate_name a.method_name) n.predicates then
        Shared.Error.elaboration
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
      validate_unique_named_decls "predicate parameter"
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
            Shared.Error.elaboration
              (Printf.sprintf "history alias '%s' uses invalid k=%d (expected >= 1)" a.alias_name a.alias_k);
          if not (String.equal a.alias_param a.alias_rhs_param) then
            Shared.Error.elaboration
              (Printf.sprintf
                 "history alias '%s' is inconsistent: parameter is '%s' but rhs uses '%s'"
                 a.alias_name a.alias_param a.alias_rhs_param);
          (a.alias_name, (a.alias_param, a.alias_k)))
        n.history_aliases;
  }

let lower_node base_env (n : S.node) : Core.Ast.node =
  validate_control_graph n;
  let env = node_env base_env n in
  validate_observers n;
  validate_method_contracts n;
  validate_method_parameters n;
  validate_method_call_graph n;
  validate_while_variants n;
  let contracts = n.contracts in
  let generated_observer_ghosts = observer_locals n.observers in
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
    expand_state_invariants n
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
    Core.Ast_builders.mk_node ~nname:n.node_name ~inputs:(lower_raw_vdecls env n.inputs)
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
              { Core.Ast.state; formula = lower_hexpr env empty_spec_context [] formula })
            state_invariants;
      };
  }

let lower_function_decl env (f : S.function_decl) : pure_function_decl =
  {
    function_name = f.function_name;
    function_params = lower_raw_vdecls env f.function_params;
    function_return = f.function_return;
    function_requires = List.map (lower_hexpr env empty_spec_context []) f.function_requires;
    function_ensures = List.map (lower_hexpr env empty_spec_context []) f.function_ensures;
    function_body = lower_expr env f.function_body;
  }

let elaborate_frontend_decl (env, type_decls, function_decls) = function
  | S.STypeDecl decl ->
      let env = add_enum_set env decl.enum_name decl.enum_constructors in
      (env, decl :: type_decls, function_decls)
	  | S.SFunctionDecl f ->
	      if List.mem_assoc f.function_name env.functions then
	        Shared.Error.elaboration (Printf.sprintf "duplicate pure function '%s'" f.function_name);
	      if List.mem_assoc f.function_name env.spec_defs then
	        Shared.Error.elaboration
	          (Printf.sprintf "pure function '%s' conflicts with a spec definition of the same name" f.function_name);
	      let lowered = lower_function_decl env f in
	      let signature = (lowered.function_params, lowered.function_return) in
	      let env = { env with functions = (lowered.function_name, signature) :: env.functions } in
	      (env, type_decls, lowered :: function_decls)
	  | S.SSpecDefDecl d ->
      validate_spec_def_decl d;
      if List.mem_assoc d.spec_def_name env.spec_defs then
        Shared.Error.elaboration (Printf.sprintf "duplicate spec definition '%s'" d.spec_def_name);
	      if List.mem_assoc d.spec_def_name env.functions then
	        Shared.Error.elaboration
	          (Printf.sprintf "spec definition '%s' conflicts with a pure function of the same name" d.spec_def_name);
	      let env = { env with spec_defs = (d.spec_def_name, d) :: env.spec_defs } in
	      (env, type_decls, function_decls)

let elaborate_source (source : S.source) : source =
  let env, type_decls, function_decls =
    List.fold_left elaborate_frontend_decl (empty_env, [], []) source.frontend_decls
  in
  {
    type_decls = List.rev type_decls;
    function_decls = List.rev function_decls;
    nodes = List.map (lower_node env) source.nodes;
  }
