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

open Core_syntax

module Abs = Ir
open Pre_k_layout

let dedup_summary_formulas (xs : Abs.summary_formula list) : Abs.summary_formula list =
  List.sort_uniq
    (fun (a : Abs.summary_formula) (b : Abs.summary_formula) ->
      Int.compare a.meta.oid b.meta.oid)
    xs

type port_view = {
  port_name : ident;
  port_type : ty;
}

type runtime_action_view =
  | ActionAssign of ident * expr
  | ActionIf of expr * runtime_action_view list * runtime_action_view list
  | ActionMatch of expr * (ident * runtime_action_view list) list * runtime_action_view list
  | ActionSkip

type action_block_kind =
  | ActionUser

type action_block_view = {
  block_kind : action_block_kind;
  block_actions : runtime_action_view list;
}

type runtime_transition_view = {
  transition_id : string;
  src_state : ident;
  dst_state : ident;
  guard : expr option;
  requires : Abs.summary_formula list;
  ensures : Abs.summary_formula list;
  body : Core_syntax.stmt list;
  action_blocks : action_block_view list;
}

type runtime_step_class =
  | StepSafe
  | StepBadGuarantee

type runtime_product_transition_view = {
  transition_id : string;
  src_state : ident;
  dst_state : ident;
  guard : expr option;
  body : Core_syntax.stmt list;
  step_class : runtime_step_class;
  product_src : Ir.product_state;
  product_dst : Ir.product_state;
  requires : Abs.summary_formula list;
  propagates : Abs.summary_formula list;
  ensures : Abs.summary_formula list;
  forbidden : Abs.summary_formula list;
}

type transition_group_view = {
  group_state : ident;
  group_transitions : runtime_transition_view list;
}

type state_branch_view = {
  branch_state : ident;
  branch_transitions : runtime_transition_view list;
}

type t = {
  node_name : ident;
  inputs : port_view list;
  outputs : port_view list;
  locals : port_view list;
  control_states : ident list;
  init_control_state : ident;
  transitions : runtime_transition_view list;
  product_transitions : runtime_product_transition_view list;
  transition_groups : transition_group_view list;
  state_branches : state_branch_view list;
  assumes : ltl list;
  guarantees : ltl list;
  init_invariant_goals : Abs.summary_formula list;
}

type known_value =
  | KnownInt of int
  | KnownBool of bool

let port_of_vdecl (v : vdecl) : port_view = { port_name = v.vname; port_type = v.vty }

let collect_ctor_expr (acc : ident list) (e : expr) : ident list =
  let rec go acc (e : expr) =
    match e.expr with
    | EVar _name -> acc
    | ELitInt _ | ELitBool _ -> acc
    | EUn (_, inner) -> go acc inner
    | EBin (_, a, b) | ECmp (_, a, b) -> go (go acc a) b
  in
  go acc e

let rec collect_ctor_hexpr (acc : ident list) (h : hexpr) : ident list =
  match h.hexpr with
  | HLitInt _ | HLitBool _ | HVar _ | HPreK _ -> acc
  | HUn (_, inner) -> collect_ctor_hexpr acc inner
  | HBin (_, a, b) | HCmp (_, a, b) ->
      collect_ctor_hexpr (collect_ctor_hexpr acc a) b

let rec collect_ctor_stmt (acc : ident list) (s : stmt) : ident list =
  match s.stmt with
  | SAssign (_, e) -> collect_ctor_expr acc e
  | SIf (c, tbr, fbr) ->
      let acc = collect_ctor_expr acc c in
      let acc = List.fold_left collect_ctor_stmt acc tbr in
      List.fold_left collect_ctor_stmt acc fbr
  | SMatch (e, branches, def) ->
      let acc = collect_ctor_expr acc e in
      let acc =
        List.fold_left (fun acc (_, body) -> List.fold_left collect_ctor_stmt acc body) acc branches
      in
      List.fold_left collect_ctor_stmt acc def
  | SCall _ -> failwith "instance calls are not supported"
  | SSkip -> acc

let rec actions_of_stmts (stmts : Core_syntax.stmt list) : runtime_action_view list =
  List.map action_of_stmt stmts

and action_of_stmt (s : Core_syntax.stmt) : runtime_action_view =
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
  | SCall _ -> failwith "instance calls are not supported"

let literal_known_value (e : expr) : known_value option =
  match e.expr with
  | ELitInt n -> Some (KnownInt n)
  | ELitBool b -> Some (KnownBool b)
  | _ -> None

let known_expr_of_value = function
  | KnownInt n -> { expr = ELitInt n; loc = None }
  | KnownBool b -> { expr = ELitBool b; loc = None }

let lookup_known (known : (ident * known_value) list) (x : ident) : known_value option =
  List.assoc_opt x known

let bind_known (known : (ident * known_value) list) (x : ident) (v : known_value) :
    (ident * known_value) list =
  (x, v) :: List.remove_assoc x known

let drop_known (known : (ident * known_value) list) (x : ident) : (ident * known_value) list =
  List.remove_assoc x known

let rec simplify_expr (known : (ident * known_value) list) (e : expr) : expr =
  let mk desc = { e with expr = desc } in
  match e.expr with
  | EVar x -> begin
      match lookup_known known x with
      | Some v -> known_expr_of_value v
      | None -> e
    end
  | ELitInt _ | ELitBool _ -> e
  | EUn (Not, inner) -> begin
      match (simplify_expr known inner).expr with
      | ELitBool b -> mk (ELitBool (not b))
      | inner' -> mk (EUn (Not, { e with expr = inner' }))
    end
  | EUn (Neg, inner) -> begin
      match (simplify_expr known inner).expr with
      | ELitInt n -> mk (ELitInt (-n))
      | inner' -> mk (EUn (Neg, { e with expr = inner' }))
    end
  | EBin (op, a, b) ->
      let a' = simplify_expr known a in
      let b' = simplify_expr known b in
      begin
        match (op, a'.expr, b'.expr) with
        | Add, ELitInt x, ELitInt y -> mk (ELitInt (x + y))
        | Sub, ELitInt x, ELitInt y -> mk (ELitInt (x - y))
        | Mul, ELitInt x, ELitInt y -> mk (ELitInt (x * y))
        | Div, ELitInt x, ELitInt y when y <> 0 -> mk (ELitInt (x / y))
        | And, ELitBool x, ELitBool y -> mk (ELitBool (x && y))
        | Or, ELitBool x, ELitBool y -> mk (ELitBool (x || y))
        | And, ELitBool true, _ -> b'
        | And, _, ELitBool true -> a'
        | And, ELitBool false, _ -> mk (ELitBool false)
        | And, _, ELitBool false -> mk (ELitBool false)
        | Or, ELitBool false, _ -> b'
        | Or, _, ELitBool false -> a'
        | Or, ELitBool true, _ -> mk (ELitBool true)
        | Or, _, ELitBool true -> mk (ELitBool true)
        | _ -> mk (EBin (op, a', b'))
      end
  | ECmp (op, a, b) ->
      let a' = simplify_expr known a in
      let b' = simplify_expr known b in
      begin
        match (op, a'.expr, b'.expr) with
        | REq, ELitInt x, ELitInt y -> mk (ELitBool (x = y))
        | REq, ELitBool x, ELitBool y -> mk (ELitBool (x = y))
        | RNeq, ELitInt x, ELitInt y -> mk (ELitBool (x <> y))
        | RNeq, ELitBool x, ELitBool y -> mk (ELitBool (x <> y))
        | RLt, ELitInt x, ELitInt y -> mk (ELitBool (x < y))
        | RLe, ELitInt x, ELitInt y -> mk (ELitBool (x <= y))
        | RGt, ELitInt x, ELitInt y -> mk (ELitBool (x > y))
        | RGe, ELitInt x, ELitInt y -> mk (ELitBool (x >= y))
        | _ -> mk (ECmp (op, a', b'))
      end

let known_from_guard (guard : expr option) : (ident * known_value) list =
  let rec gather acc (e : expr) =
    match e.expr with
    | EBin (And, a, b) -> gather (gather acc a) b
    | ECmp (REq, ({ expr = EVar x; _ } as _a), b) -> begin
        match literal_known_value b with
        | Some v -> bind_known acc x v
        | None -> acc
      end
    | ECmp (REq, a, ({ expr = EVar x; _ } as _b)) -> begin
        match literal_known_value a with
        | Some v -> bind_known acc x v
        | None -> acc
      end
    | _ -> acc
  in
  match guard with None -> [] | Some g -> gather [] g

let known_context_of_transition_guard (guard : expr option) : (ident * known_value) list =
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
      let e' = simplify_expr known e in
      let known' =
        match e'.expr with
        | EVar y -> begin
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
  | ActionIf (cond, then_actions, else_actions) ->
      let cond' = simplify_expr known cond in
      begin
        match cond'.expr with
        | ELitBool true -> simplify_actions known then_actions
        | ELitBool false -> simplify_actions known else_actions
        | _ ->
            let then_actions, _ = simplify_actions known then_actions in
            let else_actions, _ = simplify_actions known else_actions in
            ([ ActionIf (cond', then_actions, else_actions) ], known)
      end
  | ActionMatch (scrutinee, branches, default_actions) ->
      let scrutinee' = simplify_expr known scrutinee in
      let branches =
        List.map
          (fun (ctor, body) ->
            let body', _ = simplify_actions known body in
            (ctor, body'))
          branches
      in
      let default_actions, _ = simplify_actions known default_actions in
      ([ ActionMatch (scrutinee', branches, default_actions) ], known)

let action_blocks_of_transition (t : Abs.transition) : action_block_view list =
  let known = known_context_of_transition_guard t.guard_expr in
  let raw_blocks =
    [ (ActionUser, actions_of_stmts t.body_stmts) ]
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

let transition_of_ir ?transition_id (t : Abs.transition) : runtime_transition_view =
  let action_blocks = action_blocks_of_transition t in
  {
    transition_id =
      Option.value ~default:(Printf.sprintf "%s__%s" t.src_state t.dst_state) transition_id;
    src_state = t.src_state;
    dst_state = t.dst_state;
    guard = t.guard_expr;
    requires = [];
    ensures = [];
    body = t.body_stmts;
    action_blocks;
  }

let transition_of_product_step (step : runtime_product_transition_view) : runtime_transition_view =
  transition_of_ir ~transition_id:step.transition_id
    {
      src_state = step.src_state;
      dst_state = step.dst_state;
      guard_expr = step.guard;
      body_stmts = step.body;
    }

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

let program_transitions_from_summaries (summaries : Abs.product_step_summary list) :
    Abs.transition list =
  let seen : (Abs.transition, unit) Hashtbl.t = Hashtbl.create 64 in
  let ordered = ref [] in
  List.iter
    (fun (summary : Abs.product_step_summary) ->
      let step = summary.identity.program_step in
      if not (Hashtbl.mem seen step) then (
        Hashtbl.add seen step ();
        ordered := !ordered @ [ step ]))
    summaries;
  !ordered

let of_ir_node (node : Ir.node_ir) : t =
  let sem = node.semantics in
  let program_transitions = program_transitions_from_summaries node.summaries in
  let transitions =
    List.mapi
      (fun idx (t : Abs.transition) ->
        transition_of_ir ~transition_id:(Printf.sprintf "tr_%d" idx) t)
      program_transitions
  in
  let transition_groups = group_transitions transitions in
  let runtime =
    {
      node_name = sem.sem_nname;
      inputs = List.map port_of_vdecl sem.sem_inputs;
      outputs = List.map port_of_vdecl sem.sem_outputs;
      locals = List.map port_of_vdecl sem.sem_locals;
      control_states = sem.sem_states;
      init_control_state = sem.sem_init_state;
      transitions;
      product_transitions = [];
      transition_groups;
      state_branches = state_branches_of_groups transition_groups;
      assumes = node.source_info.assumes;
      guarantees = node.source_info.guarantees;
      init_invariant_goals = node.init_invariant_goals;
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
                  guard = t.guard_expr;
                  body = t.body_stmts;
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
                   guard = t.guard_expr;
                   body = t.body_stmts;
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
