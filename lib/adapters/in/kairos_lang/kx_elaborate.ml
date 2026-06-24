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
module Observers = Kx_elaborate_observers
module State_selectors = Kx_elaborate_state_selectors
module Subst = Kx_elaborate_subst
module Validation = Kx_elaborate_validation
include Kx_elaborate_env
include Kx_elaborate_histories
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
  | None -> failwith (Printf.sprintf "unknown action '%s'" name)
  | Some action ->
      if List.mem name stack then
        failwith (Printf.sprintf "cyclic action expansion involving '%s'" name);
      if List.length action.action_params <> List.length args then
        failwith
          (Printf.sprintf "action '%s' expects %d arguments but got %d" name
             (List.length action.action_params) (List.length args));
      let body =
        List.fold_left2
          (fun acc param value -> List.map (subst_stmt ~param ~value) acc)
          action.action_body action.action_params args
      in
      let instantiate formulas =
        List.fold_left2
          (fun acc param value -> List.map (subst_hexpr ~param ~value) acc)
          formulas action.action_params args
      in
      let assertion formula =
        Kx_ast_builders.mk_stmt
          (SAssert (lower_hexpr env empty_spec_context [] formula))
      in
      List.map assertion (instantiate action.action_requires)
      @ lower_stmt_list env (name :: stack) body
      @ List.map assertion (instantiate action.action_ensures)

let validate_unique_named_decls = Validation.validate_unique_named_decls
let validate_observers = Validation.validate_observers
let validate_action_contracts = Validation.validate_action_contracts
let validate_history_def_decl = Validation.validate_history_def_decl
let validate_spec_def_decl = Validation.validate_spec_def_decl
let observer_updates_for_transition = Observers.observer_updates_for_transition
let observer_locals = Observers.observer_locals
let expand_state_invariants = State_selectors.expand_state_invariants

let expand_observers_in_transition ~init_state observers (t : S.transition) =
  { t with body = t.body @ observer_updates_for_transition ~init_state observers t }

let lower_contracts env contracts =
  let assumes, guarantees =
    List.fold_left
      (fun (assumes, guarantees) -> function
        | S.SCRequires f -> (List.rev_append (lower_contract_ltls env f) assumes, guarantees)
        | S.SCEnsures f -> (assumes, List.rev_append (lower_contract_ltls env f) guarantees))
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
        failwith
          (Printf.sprintf "predicate '%s' conflicts with a pure function of the same name" p.predicate_name))
    n.predicates;
  List.iter
    (fun (p : S.predicate_decl) ->
      if List.mem_assoc p.predicate_name base_env.spec_defs then
        failwith
          (Printf.sprintf "predicate '%s' conflicts with a spec definition of the same name" p.predicate_name))
    n.predicates;
  List.iter
    (fun (p : S.predicate_decl) ->
      if List.mem_assoc p.predicate_name base_env.history_defs then
        failwith
          (Printf.sprintf "predicate '%s' conflicts with a history definition of the same name" p.predicate_name))
    n.predicates;
  List.iter
    (fun (a : S.action_decl) ->
      if List.mem_assoc a.action_name base_env.functions then
        failwith
          (Printf.sprintf "action '%s' conflicts with a pure function of the same name" a.action_name))
    n.actions;
  List.iter
    (fun (a : S.action_decl) ->
      if List.mem_assoc a.action_name base_env.spec_defs then
        failwith
          (Printf.sprintf "action '%s' conflicts with a spec definition of the same name" a.action_name))
    n.actions;
  List.iter
    (fun (a : S.action_decl) ->
      if List.mem_assoc a.action_name base_env.history_defs then
        failwith
          (Printf.sprintf "action '%s' conflicts with a history definition of the same name" a.action_name))
    n.actions;
  List.iter
    (fun (a : S.action_decl) ->
      if List.exists (fun (p : S.predicate_decl) -> String.equal p.predicate_name a.action_name) n.predicates then
        failwith
          (Printf.sprintf "action '%s' conflicts with a predicate of the same name" a.action_name))
    n.actions;
  {
    base_env with
    predicates = List.map (fun p -> (p.S.predicate_name, p)) n.predicates;
    actions = List.map (fun a -> (a.S.action_name, a)) n.actions;
    history_aliases =
      List.map
        (fun a ->
          if a.S.alias_k < 1 then
            failwith
              (Printf.sprintf "history alias '%s' uses invalid k=%d (expected >= 1)" a.alias_name a.alias_k);
          if not (String.equal a.alias_param a.alias_rhs_param) then
            failwith
              (Printf.sprintf
                 "history alias '%s' is inconsistent: parameter is '%s' but rhs uses '%s'"
                 a.alias_name a.alias_param a.alias_rhs_param);
          (a.alias_name, (a.alias_param, a.alias_k)))
        n.history_aliases;
  }

let lower_node base_env (n : S.node) : Kx_ast.node =
  let env = node_env base_env n in
  validate_observers n;
  validate_action_contracts n;
  let contracts = n.contracts in
  let generated_histories = collect_node_histories env n contracts in
  let generated_history_ghosts = history_ghosts generated_histories in
  let generated_observer_ghosts = observer_locals n.observers in
  let public_ghosts = List.map (fun (o : S.observer_decl) -> o.observer_name) n.observers in
  let input_names = List.map (fun (v : vdecl) -> v.vname) (lower_raw_vdecls env n.inputs) in
  let transitions =
    List.map
      (expand_histories_in_transition ~input_names ~init_state:n.state_decls.init_state
         generated_histories)
      n.transitions
    |> List.map
         (expand_observers_in_transition ~init_state:n.state_decls.init_state n.observers)
  in
  let assumes, guarantees = lower_contracts env contracts in
  let state_invariants = expand_state_invariants n in
  let node =
    Kx_ast_builders.mk_node ~nname:n.node_name ~inputs:(lower_raw_vdecls env n.inputs)
	  ~outputs:(lower_raw_vdecls env n.outputs) ~assumes ~guarantees ~instances:n.instances
	  ~locals:(lower_raw_vdecls env n.locals)
	  ~ghosts:(lower_raw_vdecls env (n.ghosts @ generated_history_ghosts @ generated_observer_ghosts))
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
	        failwith (Printf.sprintf "duplicate pure function '%s'" f.function_name);
	      if List.mem_assoc f.function_name env.spec_defs then
	        failwith
	          (Printf.sprintf "pure function '%s' conflicts with a spec definition of the same name" f.function_name);
	      if List.mem_assoc f.function_name env.history_defs then
	        failwith
	          (Printf.sprintf "pure function '%s' conflicts with a history definition of the same name" f.function_name);
	      let lowered = lower_function_decl env f in
	      let signature = (lowered.function_params, lowered.function_return) in
	      let env = { env with functions = (lowered.function_name, signature) :: env.functions } in
	      (env, type_decls, lowered :: function_decls)
	  | S.SSpecDefDecl d ->
      validate_spec_def_decl d;
      if List.mem_assoc d.spec_def_name env.spec_defs then
        failwith (Printf.sprintf "duplicate spec definition '%s'" d.spec_def_name);
	      if List.mem_assoc d.spec_def_name env.functions then
	        failwith
	          (Printf.sprintf "spec definition '%s' conflicts with a pure function of the same name" d.spec_def_name);
	      if List.mem_assoc d.spec_def_name env.history_defs then
	        failwith
	          (Printf.sprintf "spec definition '%s' conflicts with a history definition of the same name" d.spec_def_name);
	      let env = { env with spec_defs = (d.spec_def_name, d) :: env.spec_defs } in
	      (env, type_decls, function_decls)
	  | S.SHistoryDefDecl d ->
	      validate_history_def_decl d;
	      if List.mem_assoc d.history_def_name env.history_defs then
	        failwith (Printf.sprintf "duplicate history definition '%s'" d.history_def_name);
	      if List.mem_assoc d.history_def_name env.functions then
	        failwith
	          (Printf.sprintf "history definition '%s' conflicts with a pure function of the same name" d.history_def_name);
	      if List.mem_assoc d.history_def_name env.spec_defs then
	        failwith
	          (Printf.sprintf "history definition '%s' conflicts with a spec definition of the same name" d.history_def_name);
	      let env = { env with history_defs = (d.history_def_name, d) :: env.history_defs } in
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
