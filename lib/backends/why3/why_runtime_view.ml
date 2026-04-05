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

module Abs = Ir
open Collect

let dedup_summary_formulas (xs : Abs.summary_formula list) : Abs.summary_formula list =
  List.sort_uniq
    (fun (a : Abs.summary_formula) (b : Abs.summary_formula) ->
      Int.compare a.meta.oid b.meta.oid)
    xs

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
  callee_contract : Kernel_guided_contract.exported_summary_contract;
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
  | ActionUser

type action_block_view = {
  block_kind : action_block_kind;
  block_actions : runtime_action_view list;
}

type runtime_transition_view = {
  transition_id : string;
  src_state : Ast.ident;
  dst_state : Ast.ident;
  guard : Ast.iexpr option;
  requires : Abs.summary_formula list;
  ensures : Abs.summary_formula list;
  body : Ast.stmt list;
  action_blocks : action_block_view list;
  call_sites : call_site_view list;
}

type runtime_step_class =
  | StepSafe
  | StepBadGuarantee

type runtime_product_transition_view = {
  transition_id : string;
  src_state : Ast.ident;
  dst_state : Ast.ident;
  guard : Ast.iexpr option;
  step_class : runtime_step_class;
  product_src : Ir.product_state;
  product_dst : Ir.product_state;
  requires : Abs.summary_formula list;
  propagates : Abs.summary_formula list;
  ensures : Abs.summary_formula list;
  forbidden : Abs.summary_formula list;
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
  product_transitions : runtime_product_transition_view list;
  transition_groups : transition_group_view list;
  state_branches : state_branch_view list;
  assumes : Ast.ltl list;
  guarantees : Ast.ltl list;
  user_invariants : Ast.invariant_user list;
  coherency_goals : Abs.summary_formula list;
}

type backend_node_context = {
  program_transitions : Abs.transition list;
}

type backend_phase_context = {
  nodes : (Ast.ident * backend_node_context) list;
}

type known_value =
  | KnownInt of int
  | KnownBool of bool

let port_of_vdecl (v : Ast.vdecl) : port_view = { port_name = v.vname; port_type = v.vty }

let collect_ctor_iexpr (acc : ident list) (e : iexpr) : ident list =
  let rec go acc (e : iexpr) =
    match e.iexpr with
    | IVar _name -> acc
    | ILitInt _ | ILitBool _ -> acc
    | IPar inner -> go acc inner
    | IUn (_, inner) -> go acc inner
    | IBin (_, a, b) -> go (go acc a) b
  in
  go acc e

let collect_ctor_hexpr (acc : ident list) (h : hexpr) : ident list =
  match h with HNow e -> collect_ctor_iexpr acc e | HPreK (e, _) -> collect_ctor_iexpr acc e

let collect_ctor_fo (acc : ident list) (f : fo_atom) : ident list =
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
    callee_input_names = Ast_queries.input_names_of_node n;
    callee_output_names = Ast_queries.output_names_of_node n;
    callee_user_invariants = [];
    callee_contract;
  }

let ir_transition_of_ast_transition (t : Ast.transition) : Abs.transition =
  {
    src_state = t.src;
    dst_state = t.dst;
    guard_iexpr = t.guard;
    body_stmts = t.body;
  }

let dedup_callee_summaries (summaries : callee_summary_view list) : callee_summary_view list =
  let seen = Hashtbl.create 16 in
  let add acc summary =
    if Hashtbl.mem seen summary.callee_node_name then acc
    else (
      Hashtbl.replace seen summary.callee_node_name ();
      summary :: acc)
  in
  List.rev (List.fold_left add [] summaries)

let build_backend_node_context (source_node : Ast.node) : backend_node_context =
  let sem = source_node.semantics in
  { program_transitions = List.map ir_transition_of_ast_transition sem.sem_trans }

let build_backend_phase_context (source_program : Ast.program) : backend_phase_context =
  {
    nodes =
      List.map
        (fun (source_node : Ast.node) -> (source_node.semantics.sem_nname, build_backend_node_context source_node))
        source_program;
  }

let find_backend_node_context (context : backend_phase_context) (node_name : Ast.ident) :
    backend_node_context option =
  List.assoc_opt node_name context.nodes

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
  | _ -> None

let known_expr_of_value = function
  | KnownInt n -> { iexpr = ILitInt n; loc = None }
  | KnownBool b -> { iexpr = ILitBool b; loc = None }

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
        | Neq, ILitInt x, ILitInt y -> mk (ILitBool (x <> y))
        | Neq, ILitBool x, ILitBool y -> mk (ILitBool (x <> y))
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

let known_context_of_transition_guard (guard : iexpr option) : (ident * known_value) list =
  known_from_guard guard

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
    [ (ActionUser, actions_of_stmts t.body) ]
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

let transition_of_ast ?transition_id (t : Ast.transition) : runtime_transition_view =
  let action_blocks = action_blocks_of_transition t in
  let call_sites =
    List.concat_map (fun (block : action_block_view) -> collect_call_sites block.block_actions) action_blocks
  in
  {
    transition_id =
      Option.value ~default:(Printf.sprintf "%s__%s" t.src t.dst) transition_id;
    src_state = t.src;
    dst_state = t.dst;
    guard = t.guard;
    requires = [];
    ensures = [];
    body = t.body;
    action_blocks;
    call_sites;
  }

let transition_of_ir ?transition_id (t : Abs.transition) : runtime_transition_view =
  transition_of_ast ?transition_id
    {
      Ast.src = t.src_state;
      dst = t.dst_state;
      guard = t.guard_iexpr;
      body = t.body_stmts;
    }

let respecialize_transition_actions (t : runtime_transition_view) : runtime_transition_view =
  let known = known_context_of_transition_guard t.guard in
  let raw_blocks =
    [ (ActionUser, actions_of_stmts t.body) ]
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

let of_node ~(nodes : Ast.node list) (n : Ast.node) : t =
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
  let callee_summaries =
    let seen = Hashtbl.create 16 in
    let add acc summary =
      if Hashtbl.mem seen summary.callee_node_name then acc
      else (
        Hashtbl.replace seen summary.callee_node_name ();
        summary :: acc)
    in
    List.rev (List.fold_left add [] local_summaries)
  in
  let transitions =
    List.mapi
      (fun idx t -> transition_of_ast ~transition_id:(Printf.sprintf "tr_%d" idx) t)
      sem.sem_trans
  in
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
    product_transitions = [];
    transition_groups;
    state_branches = state_branches_of_groups transition_groups;
    assumes = spec.spec_assumes;
    guarantees = spec.spec_guarantees;
    user_invariants = [];
    coherency_goals = [];
  }

let find_callee_summary (runtime : t) (node_name : Ast.ident) : callee_summary_view option =
  List.find_opt
    (fun (summary : callee_summary_view) -> summary.callee_node_name = node_name)
    runtime.callee_summaries

let transition_to_ast (t : runtime_transition_view) : Ast.transition =
  { Ast.src = t.src_state; dst = t.dst_state; guard = t.guard; body = t.body }

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
        spec_invariants_state_rel = [];
      };
  }

let has_instance_calls (runtime : t) : bool =
  List.exists (fun (t : runtime_transition_view) -> t.call_sites <> []) runtime.transitions

let pre_k_locals_of_map (pre_k_map : (Ast.hexpr * Temporal_support.pre_k_info) list) : Ast.vdecl list =
  let infos =
    pre_k_map
    |> List.fold_left
         (fun acc (_, info) ->
           if List.exists
                (fun (existing : Temporal_support.pre_k_info) ->
                  existing.Temporal_support.names = info.Temporal_support.names)
                acc
           then
             acc
           else acc @ [ info ])
         []
  in
  infos
  |> List.concat_map (fun (info : Temporal_support.pre_k_info) ->
         List.map (fun name -> { Ast.vname = name; vty = info.vty }) info.names)

let of_ir_node ~(backend_node_context : backend_node_context) (node : Ir.node_ir) : t =
  let sem = node.context.semantics in
  let transitions =
    List.mapi
      (fun idx (t : Abs.transition) ->
        transition_of_ir ~transition_id:(Printf.sprintf "tr_%d" idx) t)
      backend_node_context.program_transitions
  in
  let transition_groups = group_transitions transitions in
  let runtime =
    {
      node_name = sem.sem_nname;
      inputs = List.map port_of_vdecl sem.sem_inputs;
      outputs = List.map port_of_vdecl sem.sem_outputs;
      locals =
        List.map port_of_vdecl (sem.sem_locals @ pre_k_locals_of_map node.context.pre_k_map);
      instances = [];
      callee_summaries = [];
      control_states = sem.sem_states;
      init_control_state = sem.sem_init_state;
      transitions;
      product_transitions = [];
      transition_groups;
      state_branches = state_branches_of_groups transition_groups;
      assumes = node.context.source_info.assumes;
      guarantees = node.context.source_info.guarantees;
      user_invariants = node.context.source_info.user_invariants;
      coherency_goals = node.goals;
    }
  in
  let product_transitions =
    List.concat_map
      (fun (pc : Ir.product_step_summary) ->
        let t = pc.identity.program_step in
        let safe_product_dsts =
          pc.safe_cases
          |> List.map (fun (case : Ir.safe_product_case) -> case.product_dst)
          |> List.sort_uniq Stdlib.compare
        in
        let admissible_guards =
          pc.safe_cases
          |> List.map (fun (case : Ir.safe_product_case) -> case.admissible_guard)
        in
        let safe_group =
          match safe_product_dsts with
          | [] -> []
          | product_dst :: _ ->
              [
                {
                  transition_id = Printf.sprintf "tr_%d" pc.trace.step_uid;
                  src_state = t.src_state;
                  dst_state = t.dst_state;
                  guard = t.guard_iexpr;
                  step_class = StepSafe;
                  product_src = pc.identity.product_src;
                  product_dst;
                  requires = pc.requires;
                  propagates = admissible_guards;
                  ensures = dedup_summary_formulas pc.ensures;
                  forbidden = [];
                };
              ]
        in
        let bad_groups =
          pc.unsafe_cases
          |> List.map (fun (case : Ir.unsafe_product_case) ->
                 {
                   transition_id = Printf.sprintf "tr_%d" pc.trace.step_uid;
                   src_state = t.src_state;
                   dst_state = t.dst_state;
                   guard = t.guard_iexpr;
                   step_class = StepBadGuarantee;
                   product_src = pc.identity.product_src;
                   product_dst = case.product_dst;
                   requires = pc.requires;
                   propagates = [];
                   ensures = [];
                   forbidden = [ case.excluded_guard ];
                 })
        in
        safe_group @ bad_groups)
      node.summaries
  in
  { runtime with product_transitions }
