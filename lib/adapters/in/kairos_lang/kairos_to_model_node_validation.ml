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

open Kairos_to_model_validation_common

let validate_node (n : Verification_model.node_model) : unit =
  let node_name = n.node_name in
  let vars = n.inputs @ n.outputs @ n.locals @ n.ghosts in
  let input_var_names = List.map (fun (v : Core_syntax.vdecl) -> v.vname) n.inputs in
  let real_var_names =
    List.map (fun (v : Core_syntax.vdecl) -> v.vname)
      (n.inputs @ n.outputs @ n.locals)
  in
  let ghost_var_names = List.map (fun (v : Core_syntax.vdecl) -> v.vname) n.ghosts in
  let public_ghost_names = n.public_ghosts in
  validate_identifier_collisions node_name n.type_decls ~vars ~states:n.states;
  let seen_vars = Hashtbl.create 32 in
  List.iter
    (fun (v : Core_syntax.vdecl) ->
      match Hashtbl.find_opt seen_vars v.vname with
      | Some () -> fail_node node_name (Printf.sprintf "duplicate variable '%s'" v.vname)
      | None -> Hashtbl.add seen_vars v.vname ())
    vars;
  List.iter
    (fun name ->
      if not (List.mem name ghost_var_names) then
        fail_node node_name
          (Printf.sprintf "public ghost '%s' is not declared as a ghost variable" name))
    public_ghost_names;
  let var_types = List.map (fun (v : Core_syntax.vdecl) -> (v.vname, v.vty)) vars in
  let find_var x =
    match List.assoc_opt x var_types with
    | Some ty -> ty
    | None -> fail_node node_name (Printf.sprintf "unknown variable '%s'" x)
  in
  let find_ctor c =
    match lookup_constructor n.type_decls c with
    | Some ty -> ty
    | None -> fail_node node_name (Printf.sprintf "unknown enum constructor '%s'" c)
  in
  let expect_ty context expected actual =
    if not (same_ty expected actual) then
      fail_node node_name
        (Printf.sprintf "%s has type %s but %s was expected" context
           (type_name actual) (type_name expected))
  in
  let is_ghost_var x = List.mem x ghost_var_names in
  let is_public_ghost_var x = List.mem x public_ghost_names in
  let function_sigs =
    List.map
      (fun (f : Core_syntax.pure_function_decl) ->
        (f.function_name, (f.function_params, f.function_return)))
      n.function_decls
  in
  let find_fun called =
    match List.assoc_opt called function_sigs with
    | Some sig_ -> sig_
    | None -> fail_node node_name (Printf.sprintf "unknown pure function '%s'" called)
  in
  let has_prefix ~(prefix : string) (s : string) : bool =
    let plen = String.length prefix in
    String.length s >= plen && String.equal (String.sub s 0 plen) prefix
  in
  let is_generated_history_var x = has_prefix ~prefix:"__kairos_history_" x in
  let reject_ghost_use ?(allow_generated_history = false)
      ?(allow_public_ghosts = false) context vars =
    match
      List.find_opt
        (fun x ->
          is_ghost_var x
          && not (allow_generated_history && is_generated_history_var x)
          && not (allow_public_ghosts && is_public_ghost_var x))
        vars
    with
    | Some x -> fail_node node_name (Printf.sprintf "%s mentions ghost variable '%s'" context x)
    | None -> ()
  in
  let reject_non_input_assumption assume_vars =
    match List.find_opt (fun x -> not (List.mem x input_var_names)) assume_vars with
    | Some x ->
        fail_node node_name
          (Printf.sprintf
             "requires contract mentions non-input variable '%s'; requires contracts may only mention declared inputs"
             x)
    | None -> ()
  in
  let rec vars_of_expr (e : Core_syntax.expr) : Core_syntax.ident list =
    match e.expr with
    | ELitInt _ | ELitBool _ | ELitEnum _ -> []
    | EVar x -> [ x ]
    | EFunCall (_, args) -> List.concat_map vars_of_expr args
    | EUn (_, inner) -> vars_of_expr inner
    | EBin (_, a, b) | ECmp (_, a, b) -> vars_of_expr a @ vars_of_expr b
  in
  let rec vars_of_hexpr (h : Core_syntax.hexpr) : Core_syntax.ident list =
    match h.hexpr with
    | HLitInt _ | HLitBool _ | HLitEnum _ -> []
    | HVar x | HPreK (x, _) -> [ x ]
    | HPred (_, args) -> List.concat_map vars_of_hexpr args
    | HFunCall (_, args) -> List.concat_map vars_of_hexpr args
    | HUn (_, inner) -> vars_of_hexpr inner
    | HBin (_, a, b) | HCmp (_, a, b) -> vars_of_hexpr a @ vars_of_hexpr b
  in
  let rec vars_of_ltl = function
    | Core_syntax.LTrue | LFalse -> []
    | LAtom (a, _, b) -> vars_of_hexpr a @ vars_of_hexpr b
    | LNot a | LX a | LG a -> vars_of_ltl a
    | LAnd (a, b) | LOr (a, b) | LImp (a, b) | LW (a, b) ->
        vars_of_ltl a @ vars_of_ltl b
  in
  let rec expr_ty (e : Core_syntax.expr) : Core_syntax.ty =
    match e.expr with
    | ELitInt _ -> TInt
    | ELitBool _ -> TBool
    | ELitEnum c -> find_ctor c
    | EVar x -> find_var x
    | EFunCall (called, args) ->
        let params, return_ty = find_fun called in
        if List.length params <> List.length args then
          fail_node node_name
            (Printf.sprintf "function '%s' expects %d arguments but got %d"
               called (List.length params) (List.length args));
        List.iter2
          (fun (param : Core_syntax.vdecl) arg ->
            expect_ty
              ("argument " ^ param.vname ^ " of function '" ^ called ^ "'")
              param.vty (expr_ty arg))
          params args;
        return_ty
    | EUn (Not, inner) ->
        expect_ty "not operand" TBool (expr_ty inner);
        TBool
    | EUn (Neg, inner) ->
        expect_ty "negation operand" TInt (expr_ty inner);
        TInt
    | EBin ((And | Or), a, b) ->
        expect_ty "left boolean operand" TBool (expr_ty a);
        expect_ty "right boolean operand" TBool (expr_ty b);
        TBool
    | EBin ((Add | Sub | Mul | Div), a, b) ->
        expect_ty "left arithmetic operand" TInt (expr_ty a);
        expect_ty "right arithmetic operand" TInt (expr_ty b);
        TInt
    | ECmp ((REq | RNeq), a, b) ->
        let ta = expr_ty a in
        let tb = expr_ty b in
        if not (same_ty ta tb) then
          fail_node node_name
            (Printf.sprintf "comparison mixes %s and %s" (type_name ta)
               (type_name tb));
        TBool
    | ECmp ((RLt | RLe | RGt | RGe), a, b) ->
        expect_ty "left ordered comparison operand" TInt (expr_ty a);
        expect_ty "right ordered comparison operand" TInt (expr_ty b);
        TBool
  in
  let rec hexpr_ty (h : Core_syntax.hexpr) : Core_syntax.ty =
    match h.hexpr with
    | HLitInt _ -> TInt
    | HLitBool _ -> TBool
    | HLitEnum c -> find_ctor c
    | HVar x -> find_var x
    | HPreK (x, _) -> find_var x
    | HPred _ -> TBool
    | HFunCall (called, args) ->
        let params, return_ty = find_fun called in
        if List.length params <> List.length args then
          fail_node node_name
            (Printf.sprintf "function '%s' expects %d arguments but got %d"
               called (List.length params) (List.length args));
        List.iter2
          (fun (param : Core_syntax.vdecl) arg ->
            expect_ty
              ("argument " ^ param.vname ^ " of function '" ^ called ^ "'")
              param.vty (hexpr_ty arg))
          params args;
        return_ty
    | HUn (Not, inner) ->
        expect_ty "not operand" TBool (hexpr_ty inner);
        TBool
    | HUn (Neg, inner) ->
        expect_ty "negation operand" TInt (hexpr_ty inner);
        TInt
    | HBin ((And | Or), a, b) ->
        expect_ty "left boolean operand" TBool (hexpr_ty a);
        expect_ty "right boolean operand" TBool (hexpr_ty b);
        TBool
    | HBin ((Add | Sub | Mul | Div), a, b) ->
        expect_ty "left arithmetic operand" TInt (hexpr_ty a);
        expect_ty "right arithmetic operand" TInt (hexpr_ty b);
        TInt
    | HCmp ((REq | RNeq), a, b) ->
        let ta = hexpr_ty a in
        let tb = hexpr_ty b in
        if not (same_ty ta tb) then
          fail_node node_name
            (Printf.sprintf "formula comparison mixes %s and %s" (type_name ta)
               (type_name tb));
        TBool
    | HCmp ((RLt | RLe | RGt | RGe), a, b) ->
        expect_ty "left ordered formula operand" TInt (hexpr_ty a);
        expect_ty "right ordered formula operand" TInt (hexpr_ty b);
        TBool
  in
  let validate_ltl_atom (h1, r, h2) =
    let t1 = hexpr_ty h1 in
    let t2 = hexpr_ty h2 in
    match r with
    | REq | RNeq ->
        if not (same_ty t1 t2) then
          fail_node node_name
            (Printf.sprintf "LTL atom compares %s with %s" (type_name t1)
               (type_name t2))
    | RLt | RLe | RGt | RGe ->
        expect_ty "left LTL ordered operand" TInt t1;
        expect_ty "right LTL ordered operand" TInt t2
  in
  let rec validate_ltl = function
    | Core_syntax.LTrue | LFalse -> ()
    | LAtom atom -> validate_ltl_atom atom
    | LNot a | LX a | LG a -> validate_ltl a
    | LAnd (a, b) | LOr (a, b) | LImp (a, b) | LW (a, b) ->
        validate_ltl a;
        validate_ltl b
  in
  let min_ticks = Historical_initialization.min_ticks_by_state n in
  let available_at_state state =
    Historical_initialization.min_ticks_for_state min_ticks state
  in
  let validate_history_availability context ~available required =
    match available with
    | None -> ()
    | Some available when required <= available -> ()
    | Some available ->
        fail_node node_name
          (Printf.sprintf
             "%s requires %d completed instant(s) of history, but only %d can be guaranteed; add enough X modalities or use an explicitly initialized history"
             context required available)
  in
  let validate_hexpr_history_availability context ~available formula =
    validate_history_availability context ~available
      (Historical_initialization.required_depth_hexpr formula)
  in
  let validate_ltl_history_availability context formula =
    validate_history_availability context ~available:(Some 0)
      (Historical_initialization.required_depth_ltl formula)
  in
  let rec stmt_writes_real (s : Core_syntax.stmt) : bool =
    match s.stmt with
    | SAssign (id, _) -> List.mem id real_var_names
    | SAssert _ -> false
    | SIf (_, then_branch, else_branch) ->
        List.exists stmt_writes_real (then_branch @ else_branch)
    | SWhile (_, _, _, body) -> List.exists stmt_writes_real body
    | SMatch (_, branches, default_branch) ->
        List.exists stmt_writes_real (List.concat_map snd branches @ default_branch)
    | SSkip -> false
    | SCall _ -> true
  in
  let stmt_list_writes_real body = List.exists stmt_writes_real body in
  let rec validate_stmt ~available (s : Core_syntax.stmt) : unit =
    match s.stmt with
    | SAssign (id, rhs) ->
        expect_ty ("assignment to " ^ id) (find_var id) (expr_ty rhs);
        if List.mem id input_var_names then
          fail_node node_name
            (Printf.sprintf "assignment cannot target input variable '%s'" id);
        if List.mem id real_var_names then
          reject_ghost_use ("assignment to non-ghost variable '" ^ id ^ "'")
            (vars_of_expr rhs)
    | SAssert formula ->
        expect_ty "assertion" TBool (hexpr_ty formula);
        validate_hexpr_history_availability "assertion" ~available formula
    | SIf (cond, then_branch, else_branch) ->
        expect_ty "if condition" TBool (expr_ty cond);
        if stmt_list_writes_real (then_branch @ else_branch) then
          reject_ghost_use "if condition" (vars_of_expr cond);
        List.iter (validate_stmt ~available) then_branch;
        List.iter (validate_stmt ~available) else_branch
    | SWhile (cond, invariants, variant, body) ->
        expect_ty "while condition" TBool (expr_ty cond);
        if stmt_list_writes_real body then
          reject_ghost_use "while condition" (vars_of_expr cond);
        List.iter
          (fun invariant ->
            expect_ty "while invariant" TBool (hexpr_ty invariant);
            validate_hexpr_history_availability "while invariant" ~available
              invariant)
          invariants;
        Option.iter
          (fun variant -> expect_ty "while variant" TInt (expr_ty variant))
          variant;
        List.iter (validate_stmt ~available) body
    | SMatch (scrutinee, branches, default_branch) ->
        let scrutinee_ty = expr_ty scrutinee in
        if stmt_list_writes_real (List.concat_map snd branches @ default_branch) then
          reject_ghost_use "match scrutinee" (vars_of_expr scrutinee);
        List.iter
          (fun (ctor, body) ->
            expect_ty ("match branch " ^ ctor) scrutinee_ty (find_ctor ctor);
            List.iter (validate_stmt ~available) body)
          branches;
        List.iter (validate_stmt ~available) default_branch
    | SSkip -> ()
    | SCall (_callee, args, outs) ->
        List.iteri
          (fun idx arg ->
            expect_ty ("call argument " ^ string_of_int (idx + 1)) (expr_ty arg)
              (expr_ty arg);
            reject_ghost_use ("call argument " ^ string_of_int (idx + 1))
              (vars_of_expr arg))
          args;
        List.iter
          (fun out ->
            if List.mem out input_var_names then
              fail_node node_name
                (Printf.sprintf
                   "call output cannot target input variable '%s'" out);
            if is_ghost_var out then
              fail_node node_name
                (Printf.sprintf "call output cannot target ghost variable '%s'" out);
            ignore (find_var out))
          outs
  in
  List.iter
    (fun (step : Verification_model.program_step) ->
      let source_available = available_at_state step.src_state in
      let destination_available = Option.map (fun n -> n + 1) source_available in
      Option.iter
        (fun guard ->
          expect_ty "transition guard" TBool (expr_ty guard);
          reject_ghost_use "transition guard" (vars_of_expr guard))
        step.guard_expr;
      List.iter (validate_stmt ~available:source_available) step.body_stmts;
      List.iter
        (fun ensure ->
          expect_ty "transition elaboration check" TBool (hexpr_ty ensure);
          validate_hexpr_history_availability "transition elaboration check"
            ~available:destination_available ensure;
          reject_ghost_use ~allow_generated_history:true
            ~allow_public_ghosts:true "transition elaboration check"
            (vars_of_hexpr ensure))
        step.elaboration_checks)
    n.steps;
  List.iter
    (fun (inv : Verification_model.state_invariant) ->
      if not (List.mem inv.state n.states) then
        fail_node node_name (Printf.sprintf "unknown invariant state '%s'" inv.state);
      if String.equal inv.state n.init_state then
        fail_node node_name
          (Printf.sprintf
             "state invariant cannot target initial state '%s'" inv.state);
      expect_ty ("invariant in " ^ inv.state) TBool (hexpr_ty inv.formula);
      validate_hexpr_history_availability ("invariant in " ^ inv.state)
        ~available:(available_at_state inv.state) inv.formula)
    n.state_invariants;
  List.iter
    (fun assume ->
      validate_ltl assume;
      validate_ltl_history_availability "requires contract" assume;
      let assume_vars = vars_of_ltl assume in
      reject_non_input_assumption assume_vars;
      reject_ghost_use ~allow_generated_history:true ~allow_public_ghosts:true
        "requires contract" assume_vars)
    n.assumes;
  List.iter
    (fun guarantee ->
      validate_ltl guarantee;
      validate_ltl_history_availability "ensures contract" guarantee;
      reject_ghost_use ~allow_generated_history:true ~allow_public_ghosts:true
        "ensures contract" (vars_of_ltl guarantee))
    n.guarantees
