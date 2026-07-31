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

open Kx_surface_syntax
open Kx_core_syntax

module S = Kx_surface_syntax
module Names = Kx_elaborate_names
module Delays = Kx_elaborate_delays
module Observers = Kx_elaborate_observers
module State_selectors = Kx_elaborate_state_selectors
module Subst = Kx_elaborate_subst
module Validation = Kx_elaborate_validation
include Kx_elaborate_env
include Kx_elaborate_logic

type source = {
  imports : S.import_decl list;
  type_decls : enum_decl list;
  function_decls : pure_function_decl list;
  nodes : Kx_ast.program;
}

let indexed_ref_name = Names.indexed_ref_name

let subst_hexpr = Subst.subst_hexpr
let subst_stmt = Subst.subst_stmt
let subst_hexpr_actual = Subst.subst_hexpr_actual
let subst_stmt_actual = Subst.subst_stmt_actual

let rec lower_stmt env stack (s : S.stmt) : Kx_ast.stmt list =
  match s.sstmt with
  | SSAssign (lhs, rhs) ->
      [ Kx_ast_builders.mk_stmt ?loc:s.sloc (SAssign (indexed_ref_name lhs, lower_expr env rhs)) ]
  | SSIf (cond, then_branch, else_branch) ->
      [
        Kx_ast_builders.mk_stmt ?loc:s.sloc
          (SIf
             ( lower_expr env cond,
               lower_stmt_list env stack then_branch,
               lower_stmt_list env stack else_branch ));
      ]
  | SSWhile (cond, invariants, variant, body) ->
      [
        Kx_ast_builders.mk_stmt ?loc:s.sloc
          (SWhile
             ( lower_expr env cond,
               List.map (lower_hexpr env empty_spec_context []) invariants,
               Option.map (lower_expr env) variant,
               lower_stmt_list env stack body ));
      ]
  | SSMatch (scrutinee, branches, default_branch) ->
      [
        Kx_ast_builders.mk_stmt ?loc:s.sloc
          (SMatch
             ( lower_expr env scrutinee,
               List.map (fun (ctor, body) -> (ctor, lower_stmt_list env stack body)) branches,
               lower_stmt_list env stack default_branch ));
      ]
  | SSSkip -> [ Kx_ast_builders.mk_stmt ?loc:s.sloc SSkip ]
  | SSCall (callee, args, outs) ->
      [ Kx_ast_builders.mk_stmt ?loc:s.sloc (SCall (callee, List.map (lower_expr env) args, outs)) ]
  | SSActionCall (callee, args) -> expand_action env stack callee args
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

and expand_action env stack name args =
  match List.assoc_opt name env.actions with
  | None -> Kx_frontend_error.elaboration (Printf.sprintf "unknown action '%s'" name)
  | Some action ->
      if List.mem name stack then
        Kx_frontend_error.elaboration (Printf.sprintf "cyclic action expansion involving '%s'" name);
      if List.length action.action_params <> List.length args then
        Kx_frontend_error.elaboration
          (Printf.sprintf "action '%s' expects %d arguments but got %d" name
             (List.length action.action_params) (List.length args));
      List.iter2
        (fun (param : S.action_param) (arg : S.expr) ->
          let actual_ty = infer_expr_type env (lower_expr env arg) in
          check_expected_type
            ~context:
              (Printf.sprintf "argument '%s' of action '%s'"
                 param.action_param_name name)
            param.action_param_ty actual_ty;
          match (param.action_param_mode, arg.sexpr) with
          | APIn, _ -> ()
          | APInOut, SEVar target
            when List.mem_assoc (indexed_ref_name target) env.variables ->
              ()
          | APInOut, SEVar target ->
              Kx_frontend_error.elaboration
                (Printf.sprintf
                   "inout parameter '%s' of action '%s' requires a writable variable, but '%s' is not a node variable"
                   param.action_param_name name (indexed_ref_name target))
          | APInOut, _ ->
              Kx_frontend_error.elaboration
                (Printf.sprintf
                   "inout parameter '%s' of action '%s' requires a variable reference argument"
                   param.action_param_name name))
        action.action_params args;
      let fresh_params =
        List.mapi
          (fun index (param : S.action_param) ->
            ( param,
              Names.generated_parameter_name "action_parameter" name index ))
          action.action_params
      in
      let renamed_body =
        List.fold_left
          (fun body ((param : S.action_param), fresh_name) ->
            List.map
              (subst_stmt ~param:param.action_param_name ~value:fresh_name)
              body)
          action.action_body fresh_params
      in
      let body =
        List.fold_left2
          (fun acc (_, fresh_name) actual ->
            List.map
              (subst_stmt_actual ~param:fresh_name ~actual)
              acc)
          renamed_body fresh_params args
      in
      let instantiate formulas =
        let renamed =
          List.fold_left
            (fun formulas ((param : S.action_param), fresh_name) ->
              List.map
                (subst_hexpr ~param:param.action_param_name
                   ~value:fresh_name)
                formulas)
            formulas fresh_params
        in
        List.fold_left2
          (fun acc (_, fresh_name) actual ->
            List.map
              (subst_hexpr_actual ~param:fresh_name ~actual)
              acc)
          renamed fresh_params args
      in
      let assertion formula =
        Kx_ast_builders.mk_stmt
          (SAssert (lower_hexpr env empty_spec_context [] formula))
      in
      List.map assertion (instantiate action.action_requires)
      @ lower_stmt_list env (name :: stack) body
      @ List.map assertion (instantiate action.action_ensures)

let validate_unique_named_decls = Validation.validate_unique_named_decls
let validate_control_graph = Validation.validate_control_graph
let validate_observers = Validation.validate_observers
let validate_action_contracts = Validation.validate_action_contracts
let validate_action_parameters = Validation.validate_action_parameters
let validate_derived_outputs = Validation.validate_derived_outputs
let validate_spec_def_decl = Validation.validate_spec_def_decl
let observer_updates_for_transition = Observers.observer_updates_for_transition
let observer_locals = Observers.observer_locals
let expand_state_invariants = State_selectors.expand_state_invariants

let expand_observers_in_transition ~init_state schedule (t : S.transition) =
  { t with body = t.body @ observer_updates_for_transition ~init_state schedule t }

let resolve_derived_outputs (n : S.node) =
  let visible_states = S.visible_states n.state_decls in
  List.map
    (fun (decl : S.derived_output_decl) ->
      let true_states =
        State_selectors.resolve_state_selector ~node_name:n.node_name
          ~states:visible_states decl.derived_output_true_states
      in
      (decl, true_states))
    n.derived_outputs

let derived_assignment dst
    ((decl, true_states) : S.derived_output_decl * ident list) =
  let value = List.exists (String.equal dst) true_states in
  let rhs = S.mk_expr ?loc:decl.derived_output_loc (SELitBool value) in
  S.mk_stmt ?loc:decl.derived_output_loc
    (SSAssign (S.mk_scalar_ref decl.derived_output_name, rhs))

let expand_derived_outputs_in_transition derived_outputs (t : S.transition) =
  {
    t with
    body = List.map (derived_assignment t.dst) derived_outputs @ t.body;
  }

let derived_output_state_invariants (n : S.node) derived_outputs =
  S.visible_states n.state_decls
  |> List.filter (fun state ->
         not (String.equal state n.state_decls.init_state))
  |> List.concat_map (fun state ->
         List.map
           (fun ((decl, true_states) :
                  S.derived_output_decl * ident list) ->
             let value = List.exists (String.equal state) true_states in
             let lhs =
               S.mk_hexpr ?loc:decl.derived_output_loc
                 (SHVar (S.mk_scalar_ref decl.derived_output_name))
             in
             let rhs =
               S.mk_hexpr ?loc:decl.derived_output_loc (SHLitBool value)
             in
             ( state,
               S.mk_hexpr ?loc:decl.derived_output_loc
                 (SHCmp (REq, lhs, rhs)) ))
           derived_outputs)

let lower_contracts ~hide_init env contracts =
  let assumes, guarantees =
    List.fold_left
      (fun (assumes, guarantees) -> function
        | S.SCRequires f -> (List.rev_append (lower_contract_ltls env f) assumes, guarantees)
        | S.SCEnsures f ->
            let f = if hide_init then S.SLX f else f in
            (assumes, List.rev_append (lower_contract_ltls env f) guarantees))
      ([], []) contracts
  in
  (List.rev assumes, List.rev guarantees)

let lower_transition env (t : S.transition) : Kx_ast.transition =
  Kx_ast_builders.mk_transition ~src:t.src ~dst:t.dst
    ~guard:(Option.map (lower_expr env) t.guard)
    ~body:(lower_stmt_list env [] t.body)
    ~ensures:(List.map (lower_hexpr env empty_spec_context []) t.ensures)
    ()

let node_env base_env (n : S.node) =
  validate_unique_named_decls "predicate" (fun (p : S.predicate_decl) -> p.predicate_name) n.predicates;
  validate_unique_named_decls "action" (fun (a : S.action_decl) -> a.action_name) n.actions;
  validate_unique_named_decls "history alias" (fun (a : S.history_alias_decl) -> a.alias_name) n.history_aliases;
  List.iter
    (fun (p : S.predicate_decl) ->
      if List.mem_assoc p.predicate_name base_env.functions then
        Kx_frontend_error.elaboration
          (Printf.sprintf "predicate '%s' conflicts with a pure function of the same name" p.predicate_name))
    n.predicates;
  List.iter
    (fun (p : S.predicate_decl) ->
      if List.mem_assoc p.predicate_name base_env.spec_defs then
        Kx_frontend_error.elaboration
          (Printf.sprintf "predicate '%s' conflicts with a spec definition of the same name" p.predicate_name))
    n.predicates;
  List.iter
    (fun (a : S.action_decl) ->
      if List.mem_assoc a.action_name base_env.functions then
        Kx_frontend_error.elaboration
          (Printf.sprintf "action '%s' conflicts with a pure function of the same name" a.action_name))
    n.actions;
  List.iter
    (fun (a : S.action_decl) ->
      if List.mem_assoc a.action_name base_env.spec_defs then
        Kx_frontend_error.elaboration
          (Printf.sprintf "action '%s' conflicts with a spec definition of the same name" a.action_name))
    n.actions;
  List.iter
    (fun (a : S.action_decl) ->
      if List.exists (fun (p : S.predicate_decl) -> String.equal p.predicate_name a.action_name) n.predicates then
        Kx_frontend_error.elaboration
          (Printf.sprintf "action '%s' conflicts with a predicate of the same name" a.action_name))
    n.actions;
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
    (fun (action : S.action_decl) ->
      List.iter
        (fun (param : S.action_param) ->
          validate_type base_env
            (Printf.sprintf "parameter '%s' of action '%s'"
               param.action_param_name action.action_name)
            param.action_param_ty)
        action.action_params)
    n.actions;
  {
    base_env with
    variables;
    predicates = List.map (fun p -> (p.S.predicate_name, p)) n.predicates;
    actions = List.map (fun a -> (a.S.action_name, a)) n.actions;
    history_aliases =
      List.map
        (fun a ->
          if a.S.alias_k < 1 then
            Kx_frontend_error.elaboration
              (Printf.sprintf "history alias '%s' uses invalid k=%d (expected >= 1)" a.alias_name a.alias_k);
          if not (String.equal a.alias_param a.alias_rhs_param) then
            Kx_frontend_error.elaboration
              (Printf.sprintf
                 "history alias '%s' is inconsistent: parameter is '%s' but rhs uses '%s'"
                 a.alias_name a.alias_param a.alias_rhs_param);
          (a.alias_name, (a.alias_param, a.alias_k)))
        n.history_aliases;
  }

let lower_node base_env (n : S.node) : Kx_ast.node =
  validate_control_graph n;
  let env = node_env base_env n in
  validate_observers n;
  validate_action_contracts n;
  validate_action_parameters n;
  validate_derived_outputs n;
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
  let observer_schedule = Observers.schedule observers in
  let generated_variables =
    lower_raw_vdecls preliminary_env generated_delay_ghosts
    |> List.map (fun (decl : vdecl) -> (decl.vname, decl.vty))
  in
  let env =
    { preliminary_env with variables = generated_variables @ preliminary_env.variables }
  in
  let public_ghosts = List.map (fun (o : S.observer_decl) -> o.observer_name) n.observers in
  let derived_outputs = resolve_derived_outputs n in
  let transitions =
    List.map (expand_derived_outputs_in_transition derived_outputs) n.transitions
    |> List.map
         (expand_observers_in_transition ~init_state:n.state_decls.init_state observer_schedule)
    |> List.map (Delays.append_commits delays)
  in
  let assumes, guarantees =
    lower_contracts ~hide_init:n.state_decls.init_is_hidden env contracts
  in
  let state_invariants =
    expand_state_invariants n
    @ derived_output_state_invariants n derived_outputs
    @ Delays.state_invariants ~states:n.state_decls.states
        ~init_state:n.state_decls.init_state delays
  in
  let node =
    Kx_ast_builders.mk_node ~nname:n.node_name ~inputs:(lower_raw_vdecls env n.inputs)
	  ~outputs:(lower_raw_vdecls env n.outputs) ~assumes ~guarantees ~instances:n.instances
	  ~locals:(lower_raw_vdecls env n.locals)
	  ~ghosts:(lower_raw_vdecls env
        (n.ghosts @ generated_observer_ghosts
       @ generated_delay_ghosts))
	  ~public_ghosts
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
              { Kx_ast.state; formula = lower_hexpr env empty_spec_context [] formula })
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
	        Kx_frontend_error.elaboration (Printf.sprintf "duplicate pure function '%s'" f.function_name);
	      if List.mem_assoc f.function_name env.spec_defs then
	        Kx_frontend_error.elaboration
	          (Printf.sprintf "pure function '%s' conflicts with a spec definition of the same name" f.function_name);
	      let lowered = lower_function_decl env f in
	      let signature = (lowered.function_params, lowered.function_return) in
	      let env = { env with functions = (lowered.function_name, signature) :: env.functions } in
	      (env, type_decls, lowered :: function_decls)
	  | S.SSpecDefDecl d ->
      validate_spec_def_decl d;
      if List.mem_assoc d.spec_def_name env.spec_defs then
        Kx_frontend_error.elaboration (Printf.sprintf "duplicate spec definition '%s'" d.spec_def_name);
	      if List.mem_assoc d.spec_def_name env.functions then
	        Kx_frontend_error.elaboration
	          (Printf.sprintf "spec definition '%s' conflicts with a pure function of the same name" d.spec_def_name);
	      let env = { env with spec_defs = (d.spec_def_name, d) :: env.spec_defs } in
	      (env, type_decls, function_decls)

let elaborate_source (source : S.source) : source =
  let env, type_decls, function_decls =
    List.fold_left elaborate_frontend_decl (empty_env, [], []) source.frontend_decls
  in
  {
    imports = source.imports;
    type_decls = List.rev type_decls;
    function_decls = List.rev function_decls;
    nodes = List.map (lower_node env) source.nodes;
  }
