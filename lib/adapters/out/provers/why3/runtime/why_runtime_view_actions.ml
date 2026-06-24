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

open Core_syntax
open Why_runtime_view_types

module StringSet = Set.Make (String)

type known_value = KnownInt of int | KnownBool of bool | KnownEnum of ident

let rec actions_of_stmts (stmts : Core_syntax.stmt list) :
    runtime_action_view list =
  List.map action_of_stmt stmts

and action_of_stmt (s : Core_syntax.stmt) : runtime_action_view =
  match s.stmt with
  | SAssign (name, expr) -> ActionAssign (name, expr)
  | SAssert formula -> ActionAssert formula
  | SIf (cond, then_branch, else_branch) ->
      ActionIf (cond, actions_of_stmts then_branch, actions_of_stmts else_branch)
  | SWhile (cond, invariants, variant, body) ->
      ActionWhile (cond, invariants, variant, actions_of_stmts body)
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
  | ELitEnum c -> Some (KnownEnum c)
  | _ -> None

let known_expr_of_value = function
  | KnownInt n -> { expr = ELitInt n; loc = None }
  | KnownBool b -> { expr = ELitBool b; loc = None }
  | KnownEnum c -> { expr = ELitEnum c; loc = None }

let lookup_known (known : (ident * known_value) list) (x : ident) :
    known_value option =
  List.assoc_opt x known

let bind_known (known : (ident * known_value) list) (x : ident)
    (v : known_value) : (ident * known_value) list =
  (x, v) :: List.remove_assoc x known

let drop_known (known : (ident * known_value) list) (x : ident) :
    (ident * known_value) list =
  List.remove_assoc x known

let rec simplify_expr (known : (ident * known_value) list) (e : expr) : expr =
  let mk desc = { e with expr = desc } in
  match e.expr with
  | EVar x -> (
      match lookup_known known x with
      | Some v -> known_expr_of_value v
      | None -> e)
  | ELitInt _ | ELitBool _ | ELitEnum _ -> e
  | EFunCall (fn, args) ->
      mk (EFunCall (fn, List.map (simplify_expr known) args))
  | EUn (Not, inner) -> (
      match (simplify_expr known inner).expr with
      | ELitBool b -> mk (ELitBool (not b))
      | inner' -> mk (EUn (Not, { e with expr = inner' })))
  | EUn (Neg, inner) -> (
      match (simplify_expr known inner).expr with
      | ELitInt n -> mk (ELitInt (-n))
      | inner' -> mk (EUn (Neg, { e with expr = inner' })))
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
        | REq, ELitEnum x, ELitEnum y -> mk (ELitBool (String.equal x y))
        | RNeq, ELitInt x, ELitInt y -> mk (ELitBool (x <> y))
        | RNeq, ELitBool x, ELitBool y -> mk (ELitBool (x <> y))
        | RNeq, ELitEnum x, ELitEnum y ->
            mk (ELitBool (not (String.equal x y)))
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
    | ECmp (REq, { expr = EVar x; _ }, b) -> (
        match literal_known_value b with
        | Some v -> bind_known acc x v
        | None -> acc)
    | ECmp (REq, a, { expr = EVar x; _ }) -> (
        match literal_known_value a with
        | Some v -> bind_known acc x v
        | None -> acc)
    | _ -> acc
  in
  match guard with None -> [] | Some g -> gather [] g

let known_context_of_transition_guard (guard : expr option) :
    (ident * known_value) list =
  known_from_guard guard

let rec simplify_actions (known : (ident * known_value) list)
    (actions : runtime_action_view list) :
    runtime_action_view list * (ident * known_value) list =
  match actions with
  | [] -> ([], known)
  | action :: rest ->
      let action', known' = simplify_action known action in
      let rest', known'' = simplify_actions known' rest in
      (action' @ rest', known'')

and simplify_action (known : (ident * known_value) list)
    (action : runtime_action_view) :
    runtime_action_view list * (ident * known_value) list =
  match action with
  | ActionSkip -> ([ ActionSkip ], known)
  | ActionAssert formula -> ([ ActionAssert formula ], known)
  | ActionAssign (x, e) ->
      let e' = simplify_expr known e in
      let known' =
        match e'.expr with
        | EVar y -> (
            match lookup_known known y with
            | Some v -> bind_known known x v
            | None -> drop_known known x)
        | _ -> (
            match literal_known_value e' with
            | Some v -> bind_known known x v
            | None -> drop_known known x)
      in
      ([ ActionAssign (x, e') ], known')
  | ActionIf (cond, then_actions, else_actions) -> (
      let cond' = simplify_expr known cond in
      match cond'.expr with
      | ELitBool true -> simplify_actions known then_actions
      | ELitBool false -> simplify_actions known else_actions
      | _ ->
          let then_actions, _ = simplify_actions known then_actions in
          let else_actions, _ = simplify_actions known else_actions in
          ([ ActionIf (cond', then_actions, else_actions) ], known))
  | ActionWhile (cond, invariants, variant, body) -> (
      let assigned = assigned_vars_of_actions body in
      let known_for_loop =
        List.filter (fun (x, _) -> not (StringSet.mem x assigned)) known
      in
      let cond' = simplify_expr known_for_loop cond in
      match cond'.expr with
      | ELitBool false -> ([ ActionSkip ], known)
      | _ ->
          let variant' = Option.map (simplify_expr known_for_loop) variant in
          let body', _ = simplify_actions known_for_loop body in
          let known_after =
            List.filter (fun (x, _) -> not (StringSet.mem x assigned)) known
          in
          ([ ActionWhile (cond', invariants, variant', body') ], known_after))
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

and assigned_vars_of_action (action : runtime_action_view) : StringSet.t =
  match action with
  | ActionAssign (x, _) -> StringSet.singleton x
  | ActionAssert _ | ActionSkip -> StringSet.empty
  | ActionIf (_, then_actions, else_actions) ->
      StringSet.union
        (assigned_vars_of_actions then_actions)
        (assigned_vars_of_actions else_actions)
  | ActionWhile (_, _, _, body) -> assigned_vars_of_actions body
  | ActionMatch (_, branches, default_actions) ->
      List.fold_left
        (fun acc (_ctor, body) ->
          StringSet.union acc (assigned_vars_of_actions body))
        (assigned_vars_of_actions default_actions)
        branches

and assigned_vars_of_actions (actions : runtime_action_view list) : StringSet.t
    =
  List.fold_left
    (fun acc action -> StringSet.union acc (assigned_vars_of_action action))
    StringSet.empty actions

let action_blocks_of_transition ~(simplify_runtime_actions : bool)
    (t : Ir.transition) : action_block_view list =
  let raw_blocks = [ (ActionUser, actions_of_stmts t.body_stmts) ] in
  let blocks =
    if not simplify_runtime_actions then raw_blocks
    else
      let known = known_context_of_transition_guard t.guard_expr in
      fst
        (List.fold_left
           (fun (acc, known) (block_kind, actions) ->
             let actions, known = simplify_actions known actions in
             ((block_kind, actions) :: acc, known))
           ([], known) raw_blocks)
      |> List.rev
  in
  List.filter_map
    (fun (block_kind, block_actions) ->
      if block_actions = [] then None else Some { block_kind; block_actions })
    blocks
