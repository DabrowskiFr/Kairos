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
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *---------------------------------------------------------------------------*)

[@@@ocaml.warning "-8-26-27-32-33"]

open Ast
open Collect

let keep_monitor_translation = ref false
let set_keep_monitor_translation (b : bool) : unit = keep_monitor_translation := b
let get_keep_monitor_translation () : bool = !keep_monitor_translation

type port_view = {
  port_name : Ast.ident;
  port_type : Ast.ty;
}

type instance_view = {
  instance_name : Ast.ident;
  callee_node_name : Ast.ident;
}

type callee_summary_view = {
  callee_node_name : Ast.ident;
  callee_inputs : port_view list;
  callee_outputs : port_view list;
  callee_locals : port_view list;
  callee_states : Ast.ident list;
  callee_input_names : Ast.ident list;
  callee_output_names : Ast.ident list;
  callee_user_invariants : Ast.invariant_user list;
  callee_state_invariants : Ast.invariant_state_rel list;
  callee_contract : Kernel_guided_contract.exported_summary_contract;
  callee_tick_summary : Product_kernel_ir.callee_tick_abi_ir option;
}

type call_site_view = {
  call_instance : Ast.ident;
  call_args : Ast.iexpr list;
  call_outputs : Ast.ident list;
}

type runtime_action_view =
  | ActionAssign of Ast.ident * Ast.iexpr
  | ActionIf of Ast.iexpr * runtime_action_view list * runtime_action_view list
  | ActionMatch of Ast.iexpr * (Ast.ident * runtime_action_view list) list * runtime_action_view list
  | ActionSkip
  | ActionCall of call_site_view

type action_block_kind =
  | ActionGhost
  | ActionUser
  | ActionInstrumentation

type action_block_view = {
  block_kind : action_block_kind;
  block_actions : runtime_action_view list;
}

type runtime_transition_view = {
  src_state : Ast.ident;
  dst_state : Ast.ident;
  guard : Ast.iexpr option;
  known_monitor_ctor : Ast.ident option;
  requires : Ast.ltl_o list;
  ensures : Ast.ltl_o list;
  ghost : Ast.stmt list;
  body : Ast.stmt list;
  instrumentation : Ast.stmt list;
  action_blocks : action_block_view list;
  call_sites : call_site_view list;
}

type transition_group_view = {
  group_state : Ast.ident;
  group_transitions : runtime_transition_view list;
}

type state_branch_view = {
  branch_state : Ast.ident;
  branch_transitions : runtime_transition_view list;
}

type t = {
  node_name : Ast.ident;
  inputs : port_view list;
  outputs : port_view list;
  locals : port_view list;
  instances : instance_view list;
  callee_summaries : callee_summary_view list;
  control_states : Ast.ident list;
  init_control_state : Ast.ident;
  transitions : runtime_transition_view list;
  transition_groups : transition_group_view list;
  state_branches : state_branch_view list;
  assumes : Ast.ltl list;
  guarantees : Ast.ltl list;
  user_invariants : Ast.invariant_user list;
  state_invariants : Ast.invariant_state_rel list;
  coherency_goals : Ast.ltl_o list;
  monitor_state_ctors : Ast.ident list;
  kernel_contract : Kernel_guided_contract.node_contract option;
}

type known_value =
  | KnownInt of int
  | KnownBool of bool
  | KnownCtor of ident

let port_of_vdecl (v : Ast.vdecl) : port_view = { port_name = v.vname; port_type = v.vty }

let is_mon_state_ctor (s : string) : bool =
  let len = String.length s in
  if len < 4 then false
  else
    String.sub s 0 3 = "Aut"
    && String.for_all (function '0' .. '9' -> true | _ -> false) (String.sub s 3 (len - 3))

let collect_ctor_iexpr (acc : ident list) (e : iexpr) : ident list =
  let add acc name = if List.mem name acc then acc else name :: acc in
  let rec go acc (e : iexpr) =
    match e.iexpr with
    | IVar name -> if is_mon_state_ctor name then add acc name else acc
    | ILitInt _ | ILitBool _ -> acc
    | IPar inner -> go acc inner
    | IUn (_, inner) -> go acc inner
    | IBin (_, a, b) -> go (go acc a) b
  in
  go acc e

let collect_ctor_hexpr (acc : ident list) (h : hexpr) : ident list =
  match h with HNow e -> collect_ctor_iexpr acc e | HPreK (e, _) -> collect_ctor_iexpr acc e

let collect_ctor_fo (acc : ident list) (f : fo) : ident list =
  match f with
  | FRel (h1, _, h2) -> collect_ctor_hexpr (collect_ctor_hexpr acc h1) h2
  | FPred (_, hs) -> List.fold_left collect_ctor_hexpr acc hs

let rec collect_ctor_ltl (acc : ident list) (f : ltl) : ident list =
  match f with
  | LTrue | LFalse -> acc
  | LAtom a -> collect_ctor_fo acc a
  | LNot a | LX a | LG a -> collect_ctor_ltl acc a
  | LAnd (a, b) | LOr (a, b) | LImp (a, b) | LW (a, b) ->
      collect_ctor_ltl (collect_ctor_ltl acc a) b

let rec collect_ctor_stmt (acc : ident list) (s : stmt) : ident list =
  match s.stmt with
  | SAssign (_, e) -> collect_ctor_iexpr acc e
  | SIf (c, tbr, fbr) ->
      let acc = collect_ctor_iexpr acc c in
      let acc = List.fold_left collect_ctor_stmt acc tbr in
      List.fold_left collect_ctor_stmt acc fbr
  | SMatch (e, branches, def) ->
      let acc = collect_ctor_iexpr acc e in
      let acc =
        List.fold_left (fun acc (_, body) -> List.fold_left collect_ctor_stmt acc body) acc branches
      in
      List.fold_left collect_ctor_stmt acc def
  | SCall (_, args, _) -> List.fold_left collect_ctor_iexpr acc args
  | SSkip -> acc

let collect_mon_state_ctors (n : Ast.node) : ident list =
  let spec = Ast.specification_of_node n in
  let acc = ref [] in
  List.iter (fun f -> acc := collect_ctor_ltl !acc f) (spec.spec_assumes @ spec.spec_guarantees);
  List.iter (fun inv -> acc := collect_ctor_hexpr !acc inv.inv_expr) n.attrs.invariants_user;
  List.iter (fun inv -> acc := collect_ctor_ltl !acc inv.formula) spec.spec_invariants_state_rel;
  List.iter (fun g -> acc := collect_ctor_ltl !acc g.value) n.attrs.coherency_goals;
  let sem = n.semantics in
  List.iter
    (fun (t : transition) ->
      List.iter
        (fun f -> acc := collect_ctor_ltl !acc f)
        (Ast_provenance.values t.requires @ Ast_provenance.values t.ensures))
    sem.sem_trans;
  List.iter
    (fun (t : transition) ->
      acc := List.fold_left collect_ctor_stmt !acc t.attrs.ghost;
      acc := List.fold_left collect_ctor_stmt !acc t.body;
      acc := List.fold_left collect_ctor_stmt !acc t.attrs.instrumentation)
    sem.sem_trans;
  let ctor_index s = try int_of_string (String.sub s 3 (String.length s - 3)) with _ -> 0 in
  List.sort (fun a b -> compare (ctor_index a) (ctor_index b)) !acc

let instance_of_pair ((instance_name, callee_node_name) : Ast.ident * Ast.ident) : instance_view =
  { instance_name; callee_node_name }

let callee_summary_of_node (n : Ast.node) : callee_summary_view =
  let callee_contract = Kernel_guided_contract.exported_summary_of_ast_node n in
  let sem = n.semantics in
  {
    callee_node_name = sem.sem_nname;
    callee_inputs = List.map port_of_vdecl sem.sem_inputs;
    callee_outputs = List.map port_of_vdecl sem.sem_outputs;
    callee_locals = List.map port_of_vdecl sem.sem_locals;
    callee_states = sem.sem_states;
    callee_input_names = Ast_utils.input_names_of_node n;
    callee_output_names = Ast_utils.output_names_of_node n;
    callee_user_invariants = n.attrs.invariants_user;
    callee_state_invariants = n.specification.spec_invariants_state_rel;
    callee_contract;
    callee_tick_summary = None;
  }

let callee_summary_of_exported_summary
    (summary : Product_kernel_ir.exported_node_summary_ir) : callee_summary_view =
  let callee_contract = Kernel_guided_contract.exported_summary_of_exported_ir summary in
  {
    callee_node_name = summary.signature.node_name;
    callee_inputs = List.map port_of_vdecl summary.signature.inputs;
    callee_outputs = List.map port_of_vdecl summary.signature.outputs;
    callee_locals = List.map port_of_vdecl summary.signature.locals;
    callee_states = summary.signature.states;
    callee_input_names = List.map (fun v -> v.vname) summary.signature.inputs;
    callee_output_names = List.map (fun v -> v.vname) summary.signature.outputs;
    callee_user_invariants = summary.user_invariants;
    callee_state_invariants = summary.state_invariants;
    callee_contract;
    callee_tick_summary = Some summary.tick_summary;
  }

let rec actions_of_stmts (stmts : Ast.stmt list) : runtime_action_view list =
  List.map action_of_stmt stmts

and action_of_stmt (s : Ast.stmt) : runtime_action_view =
  match s.stmt with
  | SAssign (name, expr) -> ActionAssign (name, expr)
  | SIf (cond, then_branch, else_branch) ->
      ActionIf (cond, actions_of_stmts then_branch, actions_of_stmts else_branch)
  | SMatch (scrutinee, branches, default_branch) ->
      let branches =
        List.map (fun (ctor, body) -> (ctor, actions_of_stmts body)) branches
      in
      ActionMatch (scrutinee, branches, actions_of_stmts default_branch)
  | SSkip -> ActionSkip
  | SCall (call_instance, call_args, call_outputs) ->
      ActionCall { call_instance; call_args; call_outputs }

let literal_known_value (e : iexpr) : known_value option =
  match e.iexpr with
  | ILitInt n -> Some (KnownInt n)
  | ILitBool b -> Some (KnownBool b)
  | IVar x when is_mon_state_ctor x -> Some (KnownCtor x)
  | _ -> None

let known_expr_of_value = function
  | KnownInt n -> { iexpr = ILitInt n; loc = None }
  | KnownBool b -> { iexpr = ILitBool b; loc = None }
  | KnownCtor x -> { iexpr = IVar x; loc = None }

let lookup_known (known : (ident * known_value) list) (x : ident) : known_value option =
  List.assoc_opt x known

let bind_known (known : (ident * known_value) list) (x : ident) (v : known_value) :
    (ident * known_value) list =
  (x, v) :: List.remove_assoc x known

let drop_known (known : (ident * known_value) list) (x : ident) : (ident * known_value) list =
  List.remove_assoc x known

let rec simplify_iexpr (known : (ident * known_value) list) (e : iexpr) : iexpr =
  let mk desc = { e with iexpr = desc } in
  match e.iexpr with
  | IVar x -> begin
      match lookup_known known x with
      | Some v -> known_expr_of_value v
      | None -> e
    end
  | ILitInt _ | ILitBool _ -> e
  | IPar inner -> simplify_iexpr known inner
  | IUn (Not, inner) -> begin
      match (simplify_iexpr known inner).iexpr with
      | ILitBool b -> mk (ILitBool (not b))
      | inner' -> mk (IUn (Not, { e with iexpr = inner' }))
    end
  | IUn (Neg, inner) -> begin
      match (simplify_iexpr known inner).iexpr with
      | ILitInt n -> mk (ILitInt (-n))
      | inner' -> mk (IUn (Neg, { e with iexpr = inner' }))
    end
  | IBin (op, a, b) ->
      let a' = simplify_iexpr known a in
      let b' = simplify_iexpr known b in
      begin
        match (op, a'.iexpr, b'.iexpr) with
        | Eq, ILitInt x, ILitInt y -> mk (ILitBool (x = y))
        | Eq, ILitBool x, ILitBool y -> mk (ILitBool (x = y))
        | Eq, IVar x, IVar y when is_mon_state_ctor x && is_mon_state_ctor y ->
            mk (ILitBool (x = y))
        | Neq, ILitInt x, ILitInt y -> mk (ILitBool (x <> y))
        | Neq, ILitBool x, ILitBool y -> mk (ILitBool (x <> y))
        | Neq, IVar x, IVar y when is_mon_state_ctor x && is_mon_state_ctor y ->
            mk (ILitBool (x <> y))
        | And, ILitBool x, ILitBool y -> mk (ILitBool (x && y))
        | Or, ILitBool x, ILitBool y -> mk (ILitBool (x || y))
        | Lt, ILitInt x, ILitInt y -> mk (ILitBool (x < y))
        | Le, ILitInt x, ILitInt y -> mk (ILitBool (x <= y))
        | Gt, ILitInt x, ILitInt y -> mk (ILitBool (x > y))
        | Ge, ILitInt x, ILitInt y -> mk (ILitBool (x >= y))
        | Add, ILitInt x, ILitInt y -> mk (ILitInt (x + y))
        | Sub, ILitInt x, ILitInt y -> mk (ILitInt (x - y))
        | Mul, ILitInt x, ILitInt y -> mk (ILitInt (x * y))
        | Div, ILitInt x, ILitInt y when y <> 0 -> mk (ILitInt (x / y))
        | And, ILitBool true, _ -> b'
        | And, _, ILitBool true -> a'
        | And, ILitBool false, _ -> mk (ILitBool false)
        | And, _, ILitBool false -> mk (ILitBool false)
        | Or, ILitBool false, _ -> b'
        | Or, _, ILitBool false -> a'
        | Or, ILitBool true, _ -> mk (ILitBool true)
        | Or, _, ILitBool true -> mk (ILitBool true)
        | _ -> mk (IBin (op, a', b'))
      end

let known_from_guard (guard : iexpr option) : (ident * known_value) list =
  let rec gather acc (e : iexpr) =
    match e.iexpr with
    | IBin (And, a, b) -> gather (gather acc a) b
    | IBin (Eq, ({ iexpr = IVar x; _ } as _a), b) -> begin
        match literal_known_value b with
        | Some v -> bind_known acc x v
        | None -> acc
      end
    | IBin (Eq, a, ({ iexpr = IVar x; _ } as _b)) -> begin
        match literal_known_value a with
        | Some v -> bind_known acc x v
        | None -> acc
      end
    | _ -> acc
  in
  match guard with None -> [] | Some g -> gather [] g

let known_context_of_transition_guard ?known_monitor_ctor (guard : iexpr option) :
    (ident * known_value) list =
  let known = known_from_guard guard in
  match known_monitor_ctor with
  | None -> known
  | Some ctor -> bind_known known "__aut_state" (KnownCtor ctor)

let rec simplify_actions (known : (ident * known_value) list) (actions : runtime_action_view list) :
    runtime_action_view list * (ident * known_value) list =
  match actions with
  | [] -> ([], known)
  | action :: rest ->
      let action', known' = simplify_action known action in
      let rest', known'' = simplify_actions known' rest in
      (action' @ rest', known'')

and simplify_action (known : (ident * known_value) list) (action : runtime_action_view) :
    runtime_action_view list * (ident * known_value) list =
  match action with
  | ActionSkip -> ([ ActionSkip ], known)
  | ActionAssign (x, e) ->
      let e' = simplify_iexpr known e in
      let known' =
        match e'.iexpr with
        | IVar y -> begin
            match lookup_known known y with
            | Some v -> bind_known known x v
            | None -> drop_known known x
          end
        | _ -> begin
            match literal_known_value e' with
            | Some v -> bind_known known x v
            | None -> drop_known known x
          end
      in
      ([ ActionAssign (x, e') ], known')
  | ActionCall { call_instance; call_args; call_outputs } ->
      let call_args = List.map (simplify_iexpr known) call_args in
      let known' = List.fold_left drop_known known call_outputs in
      ([ ActionCall { call_instance; call_args; call_outputs } ], known')
  | ActionIf (cond, then_actions, else_actions) ->
      let cond' = simplify_iexpr known cond in
      begin
        match cond'.iexpr with
        | ILitBool true -> simplify_actions known then_actions
        | ILitBool false -> simplify_actions known else_actions
        | _ ->
            let then_actions, _ = simplify_actions known then_actions in
            let else_actions, _ = simplify_actions known else_actions in
            ([ ActionIf (cond', then_actions, else_actions) ], known)
      end
  | ActionMatch (scrutinee, branches, default_actions) ->
      let scrutinee' = simplify_iexpr known scrutinee in
      let branches =
        List.map
          (fun (ctor, body) ->
            let body', _ = simplify_actions known body in
            (ctor, body'))
          branches
      in
      let default_actions, _ = simplify_actions known default_actions in
      ([ ActionMatch (scrutinee', branches, default_actions) ], known)

let rec collect_call_sites_action (acc : call_site_view list) (a : runtime_action_view) :
    call_site_view list =
  match a with
  | ActionAssign _ | ActionSkip -> acc
  | ActionCall call_site -> acc @ [ call_site ]
  | ActionIf (_, then_actions, else_actions) ->
      let acc = List.fold_left collect_call_sites_action acc then_actions in
      List.fold_left collect_call_sites_action acc else_actions
  | ActionMatch (_, branches, default_actions) ->
      let acc =
        List.fold_left
          (fun acc (_, actions) -> List.fold_left collect_call_sites_action acc actions)
          acc branches
      in
      List.fold_left collect_call_sites_action acc default_actions

let collect_call_sites (actions : runtime_action_view list) : call_site_view list =
  List.fold_left collect_call_sites_action [] actions

let action_blocks_of_transition (t : Ast.transition) : action_block_view list =
  let known = known_context_of_transition_guard t.guard in
  let raw_blocks =
    [
      (ActionGhost, actions_of_stmts t.attrs.ghost);
      (ActionUser, actions_of_stmts t.body);
      (ActionInstrumentation, actions_of_stmts t.attrs.instrumentation);
    ]
  in
  let blocks, _ =
    List.fold_left
      (fun (acc, known) (block_kind, actions) ->
        let actions, known = simplify_actions known actions in
        ((block_kind, actions) :: acc, known))
      ([], known) raw_blocks
  in
  let blocks = List.rev blocks in
  List.filter_map
    (fun (block_kind, block_actions) ->
      if block_actions = [] then None else Some { block_kind; block_actions })
    blocks

let transition_of_ast (t : Ast.transition) : runtime_transition_view =
  let action_blocks = action_blocks_of_transition t in
  let call_sites =
    List.concat_map (fun (block : action_block_view) -> collect_call_sites block.block_actions) action_blocks
  in
  {
    src_state = t.src;
    dst_state = t.dst;
    guard = t.guard;
    known_monitor_ctor = None;
    requires = t.requires;
    ensures = t.ensures;
    ghost = t.attrs.ghost;
    body = t.body;
    instrumentation = t.attrs.instrumentation;
    action_blocks;
    call_sites;
  }

let respecialize_transition_actions (t : runtime_transition_view) : runtime_transition_view =
  let known = known_context_of_transition_guard ?known_monitor_ctor:t.known_monitor_ctor t.guard in
  let raw_blocks =
    [
      (ActionGhost, actions_of_stmts t.ghost);
      (ActionUser, actions_of_stmts t.body);
      (ActionInstrumentation, actions_of_stmts t.instrumentation);
    ]
  in
  let blocks, _ =
    List.fold_left
      (fun (acc, known) (block_kind, actions) ->
        let actions, known = simplify_actions known actions in
        ((block_kind, actions) :: acc, known))
      ([], known) raw_blocks
  in
  let action_blocks =
    List.rev blocks
    |> List.filter_map (fun (block_kind, block_actions) ->
           if block_actions = [] then None else Some { block_kind; block_actions })
  in
  let call_sites =
    List.concat_map (fun (block : action_block_view) -> collect_call_sites block.block_actions) action_blocks
  in
  { t with action_blocks; call_sites }

let group_transitions (transitions : runtime_transition_view list) : transition_group_view list =
  let by_state =
    List.fold_left
      (fun acc (t : runtime_transition_view) ->
        let prev = Option.value ~default:[] (List.assoc_opt t.src_state acc) in
        (t.src_state, prev @ [ t ]) :: List.remove_assoc t.src_state acc)
      [] transitions
  in
  List.map
    (fun (group_state, group_transitions) -> { group_state; group_transitions })
    by_state

let state_branches_of_groups (groups : transition_group_view list) : state_branch_view list =
  List.map
    (fun (group : transition_group_view) ->
      { branch_state = group.group_state; branch_transitions = group.group_transitions })
    groups

let of_node ~(nodes : Ast.node list) ?(external_summaries = []) (n : Ast.node) : t =
  let sem = n.semantics in
  let spec = n.specification in
  let callee_names = List.map snd sem.sem_instances |> List.sort_uniq String.compare in
  let local_summaries =
    nodes
    |> List.filter_map (fun candidate ->
           if List.mem candidate.semantics.sem_nname callee_names then
             Some (callee_summary_of_node candidate)
           else None)
  in
  let imported_summaries =
    external_summaries
    |> List.filter_map (fun (summary : Product_kernel_ir.exported_node_summary_ir) ->
           if List.mem summary.signature.node_name callee_names then
             Some (callee_summary_of_exported_summary summary)
           else None)
  in
  let callee_summaries =
    let seen = Hashtbl.create 16 in
    let add acc summary =
      if Hashtbl.mem seen summary.callee_node_name then acc
      else (
        Hashtbl.replace seen summary.callee_node_name ();
        summary :: acc)
    in
    List.rev (List.fold_left add [] (local_summaries @ imported_summaries))
  in
  let transitions = List.map transition_of_ast sem.sem_trans in
  let transition_groups = group_transitions transitions in
  {
    node_name = sem.sem_nname;
    inputs = List.map port_of_vdecl sem.sem_inputs;
    outputs = List.map port_of_vdecl sem.sem_outputs;
    locals = List.map port_of_vdecl sem.sem_locals;
    instances = List.map instance_of_pair sem.sem_instances;
    callee_summaries;
    control_states = sem.sem_states;
    init_control_state = sem.sem_init_state;
    transitions;
    transition_groups;
    state_branches = state_branches_of_groups transition_groups;
    assumes = spec.spec_assumes;
    guarantees = spec.spec_guarantees;
    user_invariants = n.attrs.invariants_user;
    state_invariants = spec.spec_invariants_state_rel;
    coherency_goals = n.attrs.coherency_goals;
    monitor_state_ctors = collect_mon_state_ctors n;
    kernel_contract = None;
  }

let with_kernel_product_hints ?kernel_ir (runtime : t) : t =
  match kernel_ir with
  | None -> runtime
  | Some ir ->
      let kernel_contract = Some (Kernel_guided_contract.node_contract_of_ir ir) in
      let tick_map : (Ast.ident * Product_kernel_ir.callee_tick_abi_ir) list =
        ir.Product_kernel_ir.callee_tick_abis
        |> List.map
             (fun (abi : Product_kernel_ir.callee_tick_abi_ir) -> (abi.callee_node_name, abi))
      in
      let callee_summaries =
        List.map
          (fun (summary : callee_summary_view) ->
            let callee_tick_summary =
              match summary.callee_tick_summary with
              | Some _ as existing -> existing
              | None -> List.assoc_opt summary.callee_node_name tick_map
            in
            let callee_contract =
              Kernel_guided_contract.with_tick_summary callee_tick_summary summary.callee_contract
            in
            { summary with callee_tick_summary; callee_contract })
          runtime.callee_summaries
      in
      { runtime with callee_summaries; kernel_contract }

let find_callee_summary (runtime : t) (node_name : Ast.ident) : callee_summary_view option =
  List.find_opt
    (fun (summary : callee_summary_view) -> summary.callee_node_name = node_name)
    runtime.callee_summaries

let transition_to_ast (t : runtime_transition_view) : Ast.transition =
  {
    Ast.src = t.src_state;
    dst = t.dst_state;
    guard = t.guard;
    requires = t.requires;
    ensures = t.ensures;
    body = t.body;
    attrs = { uid = None; ghost = t.ghost; instrumentation = t.instrumentation; warnings = [] };
  }

let to_ast_node (runtime : t) : Ast.node =
  {
    semantics =
      {
        Ast.sem_nname = runtime.node_name;
        sem_inputs =
          List.map (fun (p : port_view) -> { Ast.vname = p.port_name; vty = p.port_type }) runtime.inputs;
        sem_outputs =
          List.map (fun (p : port_view) -> { Ast.vname = p.port_name; vty = p.port_type }) runtime.outputs;
        sem_instances =
          List.map
            (fun (i : instance_view) -> (i.instance_name, i.callee_node_name))
            runtime.instances;
        sem_locals =
          List.map (fun (p : port_view) -> { Ast.vname = p.port_name; vty = p.port_type }) runtime.locals;
        sem_states = runtime.control_states;
        sem_init_state = runtime.init_control_state;
        sem_trans = List.map transition_to_ast runtime.transitions;
      };
    specification =
      {
        Ast.spec_assumes = runtime.assumes;
        spec_guarantees = runtime.guarantees;
        spec_invariants_state_rel = runtime.state_invariants;
      };
    attrs =
      {
        uid = None;
        invariants_user = runtime.user_invariants;
        coherency_goals = runtime.coherency_goals;
      };
  }

let has_instance_calls (runtime : t) : bool =
  List.exists (fun (t : runtime_transition_view) -> t.call_sites <> []) runtime.transitions

(* ---------------------------------------------------------------------------
   IR-based construction (no OBC+ AST required)
   --------------------------------------------------------------------------- *)

let is_monitor_ctor (name : Ast.ident) : bool =
  let len = String.length name in
  len >= 4
  && String.sub name 0 3 = "Aut"
  && String.for_all (function '0' .. '9' -> true | _ -> false) (String.sub name 3 (len - 3))

let rec mentions_monitor_iexpr (e : Ast.iexpr) =
  match e.iexpr with
  | Ast.IVar name -> name = "__aut_state" || is_monitor_ctor name
  | Ast.ILitInt _ | Ast.ILitBool _ -> false
  | Ast.IPar inner | Ast.IUn (_, inner) -> mentions_monitor_iexpr inner
  | Ast.IBin (_, a, b) -> mentions_monitor_iexpr a || mentions_monitor_iexpr b

let mentions_monitor_hexpr = function
  | Ast.HNow e | Ast.HPreK (e, _) -> mentions_monitor_iexpr e

let rec mentions_monitor_ltl = function
  | Ast.LTrue | Ast.LFalse -> false
  | Ast.LAtom (Ast.FRel (h1, _, h2)) -> mentions_monitor_hexpr h1 || mentions_monitor_hexpr h2
  | Ast.LAtom (Ast.FPred (_, hs)) -> List.exists mentions_monitor_hexpr hs
  | Ast.LNot a | Ast.LX a | Ast.LG a -> mentions_monitor_ltl a
  | Ast.LAnd (a, b) | Ast.LOr (a, b) | Ast.LImp (a, b) | Ast.LW (a, b) ->
      mentions_monitor_ltl a || mentions_monitor_ltl b

let strip_monitor_contracts (contracts : Ast.ltl_o list) : Ast.ltl_o list =
  if !keep_monitor_translation then contracts
  else List.filter (fun (f : Ast.ltl_o) -> not (mentions_monitor_ltl f.value)) contracts

let rec mentions_monitor_stmt (s : Ast.stmt) =
  match s.stmt with
  | Ast.SAssign (name, expr) -> String.equal name "__aut_state" || mentions_monitor_iexpr expr
  | Ast.SIf (cond, then_branch, else_branch) ->
      mentions_monitor_iexpr cond
      || List.exists mentions_monitor_stmt then_branch
      || List.exists mentions_monitor_stmt else_branch
  | Ast.SMatch (scrutinee, branches, default_branch) ->
      mentions_monitor_iexpr scrutinee
      || List.exists
           (fun (_ctor, body) -> List.exists mentions_monitor_stmt body)
           branches
      || List.exists mentions_monitor_stmt default_branch
  | Ast.SCall (_inst, args, _outs) -> List.exists mentions_monitor_iexpr args
  | Ast.SSkip -> false

let strip_monitor_stmts (stmts : Ast.stmt list) : Ast.stmt list =
  if !keep_monitor_translation then stmts
  else List.filter (fun stmt -> not (mentions_monitor_stmt stmt)) stmts

let pre_k_updates_of_map (pre_k_map : (Ast.hexpr * Support.pre_k_info) list) : Ast.stmt list =
  let s desc = { Ast.stmt = desc; loc = None } in
  let mk_var name = { Ast.iexpr = IVar name; loc = None } in
  let pre_k_infos =
    pre_k_map
    |> List.fold_left
         (fun acc (_, info) ->
           if List.exists
                (fun (existing : Support.pre_k_info) ->
                  existing.Support.expr = info.Support.expr
                  && existing.Support.names = info.Support.names)
                acc
           then
             acc
           else acc @ [ info ])
         []
  in
  List.concat_map
    (fun (info : Support.pre_k_info) ->
      let names = info.names in
      let shifts =
        let rec loop i acc =
          if i <= 1 then acc
          else
            let tgt = List.nth names (i - 1) in
            let src = List.nth names (i - 2) in
            loop (i - 1) (acc @ [ s (SAssign (tgt, mk_var src)) ])
        in
        loop (List.length names) []
      in
      let first =
        match names with
        | [] -> []
        | name :: _ -> [ s (SAssign (name, info.expr)) ]
      in
      shifts @ first)
    pre_k_infos

let synthetic_transition_of_ir ~(pre_k_updates : Ast.stmt list)
    (t : Product_kernel_ir.reactive_transition_ir) : Ast.transition =
  {
    Ast.src = t.src_state;
    dst = t.dst_state;
    guard = t.guard_iexpr;
    requires = strip_monitor_contracts t.requires;
    ensures = strip_monitor_contracts t.ensures;
    body = t.body_stmts;
    attrs =
      {
        uid = None;
        ghost = strip_monitor_stmts t.ghost_stmts;
        instrumentation = strip_monitor_stmts t.instrumentation_stmts @ pre_k_updates;
        warnings = [];
      };
  }

(* ---------------------------------------------------------------------------
   Verified-node construction (Pass 5 output → runtime view)
   --------------------------------------------------------------------------- *)

(** Convert a [verified_transition] to an [Ast.transition] suitable for
    [transition_of_ast].  The [pre_k_updates] are appended to the
    instrumentation block, mirroring what [synthetic_transition_of_ir] does for
    the IR path. *)
let ast_of_verified_transition (t : Kairos_ir.verified_transition) : Ast.transition =
  {
    Ast.src = t.src_state;
    dst = t.dst_state;
    guard = t.guard_iexpr;
    requires = strip_monitor_contracts t.requires;
    ensures = strip_monitor_contracts t.ensures;
    body = t.body_stmts;
    attrs =
      {
        uid = None;
        ghost = strip_monitor_stmts t.ghost_stmts;
        instrumentation = strip_monitor_stmts t.instrumentation_stmts @ t.pre_k_updates;
        warnings = [];
      };
  }

(** Build a synthetic [Ast.node] from a [verified_node] for use with
    [of_node] and [collect_mon_state_ctors]. *)
let ast_node_of_verified_node (vn : Kairos_ir.verified_node) : Ast.node =
  {
    semantics =
      {
        Ast.sem_nname = vn.node_name;
        sem_inputs = vn.inputs;
        sem_outputs = vn.outputs;
        sem_instances = vn.instances;
        sem_locals =
          if !keep_monitor_translation then vn.locals
          else List.filter (fun (v : Ast.vdecl) -> v.vname <> "__aut_state") vn.locals;
        sem_states = vn.control_states;
        sem_init_state = vn.init_state;
        sem_trans = List.map ast_of_verified_transition vn.transitions;
      };
    specification =
      {
        Ast.spec_assumes = vn.assumes;
        spec_guarantees = vn.guarantees;
        spec_invariants_state_rel = vn.state_invariants;
      };
    attrs =
      {
        uid = None;
        invariants_user = vn.user_invariants;
        coherency_goals = vn.coherency_goals;
      };
  }

(** Build a full [Why_runtime_view.t] from a [verified_node].

    Local callee summaries are resolved from [program_verified_nodes] by
    converting them to synthetic [Ast.node]s.  External callee summaries are
    resolved from [external_summaries] as usual.  This replaces
    [of_exported_summary] for the new pipeline path. *)
let of_verified_node ?(external_summaries = [])
    ~(program_verified_nodes : Kairos_ir.verified_node list)
    (vn : Kairos_ir.verified_node) : t =
  let synthetic_node = ast_node_of_verified_node vn in
  let callee_nodes = List.map ast_node_of_verified_node program_verified_nodes in
  of_node ~nodes:callee_nodes ~external_summaries synthetic_node

let of_exported_summary ?(external_summaries = [])
    ~(program_summaries : Product_kernel_ir.exported_node_summary_ir list)
    (summary : Product_kernel_ir.exported_node_summary_ir) : t =
  let pre_k_updates = pre_k_updates_of_map summary.pre_k_map in
  let synthetic_trans =
    List.map
      (synthetic_transition_of_ir ~pre_k_updates)
      summary.normalized_ir.reactive_program.transitions
  in
  let all_vdecls =
    if !keep_monitor_translation then summary.signature.locals
    else List.filter (fun (v : vdecl) -> v.vname <> "__aut_state") summary.signature.locals
  in
  let callee_names =
    List.map snd summary.signature.instances |> List.sort_uniq String.compare
  in
  let local_summaries =
    program_summaries
    |> List.filter_map (fun (s : Product_kernel_ir.exported_node_summary_ir) ->
           if List.mem s.signature.node_name callee_names
           then Some (callee_summary_of_exported_summary s)
           else None)
  in
  let imported_summaries =
    external_summaries
    |> List.filter_map (fun (s : Product_kernel_ir.exported_node_summary_ir) ->
           if List.mem s.signature.node_name callee_names
           then Some (callee_summary_of_exported_summary s)
           else None)
  in
  let callee_summaries =
    let seen = Hashtbl.create 16 in
    let add acc (s : callee_summary_view) =
      if Hashtbl.mem seen s.callee_node_name then acc
      else (
        Hashtbl.replace seen s.callee_node_name ();
        s :: acc)
    in
    List.rev (List.fold_left add [] (local_summaries @ imported_summaries))
  in
  let synthetic_node : Ast.node =
    {
      semantics =
        {
          Ast.sem_nname = summary.signature.node_name;
          sem_inputs = summary.signature.inputs;
          sem_outputs = summary.signature.outputs;
          sem_instances = summary.signature.instances;
          sem_locals = all_vdecls;
          sem_states = summary.signature.states;
          sem_init_state = summary.signature.init_state;
          sem_trans = synthetic_trans;
        };
      specification =
        {
          Ast.spec_assumes = summary.assumes;
          spec_guarantees = summary.guarantees;
          spec_invariants_state_rel = summary.state_invariants;
        };
      attrs =
        {
          uid = None;
          invariants_user = summary.user_invariants;
          coherency_goals = summary.coherency_goals;
        };
    }
  in
  let transitions = List.map transition_of_ast synthetic_trans in
  let transition_groups = group_transitions transitions in
  {
    node_name = summary.signature.node_name;
    inputs = List.map port_of_vdecl summary.signature.inputs;
    outputs = List.map port_of_vdecl summary.signature.outputs;
    locals = List.map port_of_vdecl all_vdecls;
    instances = List.map instance_of_pair summary.signature.instances;
    callee_summaries;
    control_states = summary.signature.states;
    init_control_state = summary.signature.init_state;
    transitions;
    transition_groups;
    state_branches = state_branches_of_groups transition_groups;
    assumes = summary.assumes;
    guarantees = summary.guarantees;
    user_invariants = summary.user_invariants;
    state_invariants = summary.state_invariants;
    coherency_goals = summary.coherency_goals;
    monitor_state_ctors = collect_mon_state_ctors synthetic_node;
    kernel_contract = Some (Kernel_guided_contract.node_contract_of_ir summary.normalized_ir);
  }
