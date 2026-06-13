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

let loc (source_loc : Kx_loc.loc) : Loc.loc =
  {
    line = source_loc.line;
    col = source_loc.col;
    line_end = source_loc.line_end;
    col_end = source_loc.col_end;
  }

let lower_ty (ty : Kx_core_syntax.ty) : Core_syntax.ty =
  match ty with
  | Kx_core_syntax.TInt -> Core_syntax.TInt
  | Kx_core_syntax.TBool -> Core_syntax.TBool
  | Kx_core_syntax.TReal -> Core_syntax.TReal
  | Kx_core_syntax.TCustom name -> Core_syntax.TCustom name

let lower_enum_decl (decl : Kx_core_syntax.enum_decl) : Core_syntax.enum_decl =
  {
    Core_syntax.enum_name = decl.enum_name;
    enum_constructors = decl.enum_constructors;
  }

let lower_binop (op : Kx_core_syntax.binop) : Core_syntax.binop =
  match op with
  | Kx_core_syntax.Add -> Core_syntax.Add
  | Kx_core_syntax.Sub -> Core_syntax.Sub
  | Kx_core_syntax.Mul -> Core_syntax.Mul
  | Kx_core_syntax.Div -> Core_syntax.Div
  | Kx_core_syntax.And -> Core_syntax.And
  | Kx_core_syntax.Or -> Core_syntax.Or

let lower_unop (op : Kx_core_syntax.unop) : Core_syntax.unop =
  match op with
  | Kx_core_syntax.Neg -> Core_syntax.Neg
  | Kx_core_syntax.Not -> Core_syntax.Not

let lower_relop (op : Kx_core_syntax.relop) : Core_syntax.relop =
  match op with
  | Kx_core_syntax.REq -> Core_syntax.REq
  | Kx_core_syntax.RNeq -> Core_syntax.RNeq
  | Kx_core_syntax.RLt -> Core_syntax.RLt
  | Kx_core_syntax.RLe -> Core_syntax.RLe
  | Kx_core_syntax.RGt -> Core_syntax.RGt
  | Kx_core_syntax.RGe -> Core_syntax.RGe

let fail_node node_name msg =
  failwith (Printf.sprintf "Type error in node %s: %s" node_name msg)

let lookup_constructor (type_decls : Core_syntax.enum_decl list) (ctor : Core_syntax.ident) :
    Core_syntax.ty option =
  type_decls
  |> List.find_map (fun (decl : Core_syntax.enum_decl) ->
         if List.mem ctor decl.enum_constructors then Some (Core_syntax.TCustom decl.enum_name)
         else None)

let validate_unique_type_decls (type_decls : Core_syntax.enum_decl list) : unit =
  let type_names = Hashtbl.create 16 in
  let ctors = Hashtbl.create 32 in
  List.iter
    (fun (decl : Core_syntax.enum_decl) ->
      if String.equal decl.enum_name "state" then
        failwith "Type error: enum type name 'state' is reserved by the Kairos control-state encoding";
      if Hashtbl.mem type_names decl.enum_name then
        failwith (Printf.sprintf "Type error: duplicate enum type '%s'" decl.enum_name);
      Hashtbl.add type_names decl.enum_name ();
      if decl.enum_constructors = [] then
        failwith (Printf.sprintf "Type error: enum type '%s' has no constructors" decl.enum_name);
      List.iter
        (fun ctor ->
          match Hashtbl.find_opt ctors ctor with
          | Some previous ->
              failwith
                (Printf.sprintf
                   "Type error: enum constructor '%s' is declared in both '%s' and '%s'"
                   ctor previous decl.enum_name)
          | None -> Hashtbl.add ctors ctor decl.enum_name)
        decl.enum_constructors)
    type_decls

let validate_identifier_collisions node_name (type_decls : Core_syntax.enum_decl list)
    ~(vars : Core_syntax.vdecl list) ~(states : Core_syntax.ident list) : unit =
  let ctor_names =
    type_decls |> List.concat_map (fun (decl : Core_syntax.enum_decl) -> decl.enum_constructors)
  in
  let reject_collision kind name =
    if List.mem name ctor_names then
      fail_node node_name
        (Printf.sprintf "%s '%s' conflicts with an enum constructor" kind name)
  in
  List.iter (fun (v : Core_syntax.vdecl) -> reject_collision "variable" v.vname) vars;
  List.iter (reject_collision "state") states

let rec expr ~(type_decls : Core_syntax.enum_decl list) (source_expr : Kx_core_syntax.expr) :
    Core_syntax.expr =
  let lowered =
    match source_expr.expr with
    | Kx_core_syntax.ELitInt n -> Core_syntax.ELitInt n
    | Kx_core_syntax.ELitBool b -> Core_syntax.ELitBool b
    | Kx_core_syntax.EVar v -> (
        match lookup_constructor type_decls v with
        | Some _ -> Core_syntax.ELitEnum v
        | None -> Core_syntax.EVar v)
    | Kx_core_syntax.EBin (op, a, b) ->
        Core_syntax.EBin (lower_binop op, expr ~type_decls a, expr ~type_decls b)
    | Kx_core_syntax.ECmp (op, a, b) ->
        Core_syntax.ECmp (lower_relop op, expr ~type_decls a, expr ~type_decls b)
    | Kx_core_syntax.EUn (op, inner) -> Core_syntax.EUn (lower_unop op, expr ~type_decls inner)
  in
  { Core_syntax.expr = lowered; loc = Option.map loc source_expr.loc }

let rec hexpr ~(type_decls : Core_syntax.enum_decl list) (source_hexpr : Kx_core_syntax.hexpr) :
    Core_syntax.hexpr =
  let lowered =
    match source_hexpr.hexpr with
    | Kx_core_syntax.HLitInt n -> Core_syntax.HLitInt n
    | Kx_core_syntax.HLitBool b -> Core_syntax.HLitBool b
    | Kx_core_syntax.HVar v -> (
        match lookup_constructor type_decls v with
        | Some _ -> Core_syntax.HLitEnum v
        | None -> Core_syntax.HVar v)
    | Kx_core_syntax.HPreK (v, k) -> Core_syntax.HPreK (v, k)
    | Kx_core_syntax.HPred (id, hs) ->
        Core_syntax.HPred (id, List.map (hexpr ~type_decls) hs)
    | Kx_core_syntax.HBin (op, a, b) ->
        Core_syntax.HBin (lower_binop op, hexpr ~type_decls a, hexpr ~type_decls b)
    | Kx_core_syntax.HCmp (op, a, b) ->
        Core_syntax.HCmp (lower_relop op, hexpr ~type_decls a, hexpr ~type_decls b)
    | Kx_core_syntax.HUn (op, inner) -> Core_syntax.HUn (lower_unop op, hexpr ~type_decls inner)
  in
  { Core_syntax.hexpr = lowered; loc = Option.map loc source_hexpr.loc }

let rec ltl ~(type_decls : Core_syntax.enum_decl list) (source_ltl : Kx_core_syntax.ltl) :
    Core_syntax.ltl =
  match source_ltl with
  | Kx_core_syntax.LTrue -> Core_syntax.LTrue
  | Kx_core_syntax.LFalse -> Core_syntax.LFalse
  | Kx_core_syntax.LAtom (h1, r, h2) ->
      Core_syntax.LAtom (hexpr ~type_decls h1, lower_relop r, hexpr ~type_decls h2)
  | Kx_core_syntax.LNot a -> Core_syntax.LNot (ltl ~type_decls a)
  | Kx_core_syntax.LAnd (a, b) -> Core_syntax.LAnd (ltl ~type_decls a, ltl ~type_decls b)
  | Kx_core_syntax.LOr (a, b) -> Core_syntax.LOr (ltl ~type_decls a, ltl ~type_decls b)
  | Kx_core_syntax.LImp (a, b) -> Core_syntax.LImp (ltl ~type_decls a, ltl ~type_decls b)
  | Kx_core_syntax.LX a -> Core_syntax.LX (ltl ~type_decls a)
  | Kx_core_syntax.LG a -> Core_syntax.LG (ltl ~type_decls a)
  | Kx_core_syntax.LW (a, b) -> Core_syntax.LW (ltl ~type_decls a, ltl ~type_decls b)

let lower_vdecl (v : Kx_core_syntax.vdecl) : Core_syntax.vdecl =
  { vname = v.vname; vty = lower_ty v.vty }

let lower_state_invariant ~(type_decls : Core_syntax.enum_decl list)
    (inv : Kx_ast.invariant_state_rel) : Verification_model.state_invariant =
  { Verification_model.state = inv.state; formula = hexpr ~type_decls inv.formula }

let rec stmt ~(type_decls : Core_syntax.enum_decl list) (source_stmt : Kx_ast.stmt) :
    Core_syntax.stmt =
  let lowered =
    match source_stmt.stmt with
    | Kx_ast.SAssign (id, e) -> Core_syntax.SAssign (id, expr ~type_decls e)
    | Kx_ast.SIf (c, t, e) ->
        Core_syntax.SIf (expr ~type_decls c, List.map (stmt ~type_decls) t, List.map (stmt ~type_decls) e)
    | Kx_ast.SMatch (e, branches, dflt) ->
        Core_syntax.SMatch
          ( expr ~type_decls e,
            List.map (fun (ctor, body) -> (ctor, List.map (stmt ~type_decls) body)) branches,
            List.map (stmt ~type_decls) dflt )
    | Kx_ast.SSkip -> Core_syntax.SSkip
    | Kx_ast.SCall (callee, args, outs) -> Core_syntax.SCall (callee, List.map (expr ~type_decls) args, outs)
  in
  { Core_syntax.stmt = lowered; loc = Option.map loc source_stmt.loc }

let step ~(type_decls : Core_syntax.enum_decl list) (source_transition : Kx_ast.transition) :
    Verification_model.program_step =
  {
    Verification_model.src_state = source_transition.src;
    dst_state = source_transition.dst;
    guard_expr = Option.map (expr ~type_decls) source_transition.guard;
    body_stmts = List.map (stmt ~type_decls) source_transition.body;
  }

let type_name = function
  | Core_syntax.TInt -> "int"
  | TBool -> "bool"
  | TReal -> "real"
  | TCustom name -> name

let same_ty (a : Core_syntax.ty) (b : Core_syntax.ty) : bool = a = b

let validate_node (n : Verification_model.node_model) : unit =
  let node_name = n.node_name in
  let vars = n.inputs @ n.outputs @ n.locals @ n.ghosts in
  let real_var_names = List.map (fun (v : Core_syntax.vdecl) -> v.vname) (n.inputs @ n.outputs @ n.locals) in
  let ghost_var_names = List.map (fun (v : Core_syntax.vdecl) -> v.vname) n.ghosts in
  validate_identifier_collisions node_name n.type_decls ~vars ~states:n.states;
  let seen_vars = Hashtbl.create 32 in
  List.iter
    (fun (v : Core_syntax.vdecl) ->
      match Hashtbl.find_opt seen_vars v.vname with
      | Some () -> fail_node node_name (Printf.sprintf "duplicate variable '%s'" v.vname)
      | None -> Hashtbl.add seen_vars v.vname ())
    vars;
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
        (Printf.sprintf "%s has type %s but %s was expected" context (type_name actual)
           (type_name expected))
  in
  let is_ghost_var x = List.mem x ghost_var_names in
  let reject_ghost_use context vars =
    match List.find_opt is_ghost_var vars with
    | Some x -> fail_node node_name (Printf.sprintf "%s mentions ghost variable '%s'" context x)
    | None -> ()
  in
  let rec vars_of_expr (e : Core_syntax.expr) : Core_syntax.ident list =
    match e.expr with
    | ELitInt _ | ELitBool _ | ELitEnum _ -> []
    | EVar x -> [ x ]
    | EUn (_, inner) -> vars_of_expr inner
    | EBin (_, a, b) | ECmp (_, a, b) -> vars_of_expr a @ vars_of_expr b
  in
  let rec vars_of_hexpr (h : Core_syntax.hexpr) : Core_syntax.ident list =
    match h.hexpr with
    | HLitInt _ | HLitBool _ | HLitEnum _ -> []
    | HVar x | HPreK (x, _) -> [ x ]
    | HPred (_, args) -> List.concat_map vars_of_hexpr args
    | HUn (_, inner) -> vars_of_hexpr inner
    | HBin (_, a, b) | HCmp (_, a, b) -> vars_of_hexpr a @ vars_of_hexpr b
  in
  let rec vars_of_ltl = function
    | Core_syntax.LTrue | LFalse -> []
    | LAtom (a, _, b) -> vars_of_hexpr a @ vars_of_hexpr b
    | LNot a | LX a | LG a -> vars_of_ltl a
    | LAnd (a, b) | LOr (a, b) | LImp (a, b) | LW (a, b) -> vars_of_ltl a @ vars_of_ltl b
  in
  let rec expr_ty (e : Core_syntax.expr) : Core_syntax.ty =
    match e.expr with
    | ELitInt _ -> TInt
    | ELitBool _ -> TBool
    | ELitEnum c -> find_ctor c
    | EVar x -> find_var x
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
            (Printf.sprintf "comparison mixes %s and %s" (type_name ta) (type_name tb));
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
            (Printf.sprintf "formula comparison mixes %s and %s" (type_name ta) (type_name tb));
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
            (Printf.sprintf "LTL atom compares %s with %s" (type_name t1) (type_name t2))
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
  let rec validate_stmt (s : Core_syntax.stmt) : unit =
    match s.stmt with
    | SAssign (id, rhs) ->
        expect_ty ("assignment to " ^ id) (find_var id) (expr_ty rhs);
        if List.mem id real_var_names then
          reject_ghost_use ("assignment to non-ghost variable '" ^ id ^ "'")
            (vars_of_expr rhs)
    | SIf (cond, then_branch, else_branch) ->
        expect_ty "if condition" TBool (expr_ty cond);
        reject_ghost_use "if condition" (vars_of_expr cond);
        List.iter validate_stmt then_branch;
        List.iter validate_stmt else_branch
    | SMatch (scrutinee, branches, default_branch) ->
        let scrutinee_ty = expr_ty scrutinee in
        reject_ghost_use "match scrutinee" (vars_of_expr scrutinee);
        List.iter
          (fun (ctor, body) ->
            expect_ty ("match branch " ^ ctor) scrutinee_ty (find_ctor ctor);
            List.iter validate_stmt body)
          branches;
        List.iter validate_stmt default_branch
    | SSkip -> ()
    | SCall (_callee, args, outs) ->
        List.iteri
          (fun idx arg ->
            expect_ty ("call argument " ^ string_of_int (idx + 1)) (expr_ty arg) (expr_ty arg);
            reject_ghost_use ("call argument " ^ string_of_int (idx + 1)) (vars_of_expr arg))
          args;
        List.iter
          (fun out ->
            if is_ghost_var out then
              fail_node node_name
                (Printf.sprintf "call output cannot target ghost variable '%s'" out);
            ignore (find_var out))
          outs
  in
  List.iter
    (fun (step : Verification_model.program_step) ->
      Option.iter
        (fun guard ->
          expect_ty "transition guard" TBool (expr_ty guard);
          reject_ghost_use "transition guard" (vars_of_expr guard))
        step.guard_expr;
      List.iter validate_stmt step.body_stmts)
    n.steps;
  List.iter (fun (inv : Verification_model.state_invariant) ->
      if not (List.mem inv.state n.states) then
        fail_node node_name (Printf.sprintf "unknown invariant state '%s'" inv.state);
      expect_ty ("invariant in " ^ inv.state) TBool (hexpr_ty inv.formula))
    n.state_invariants;
  List.iter
    (fun assume ->
      validate_ltl assume;
      reject_ghost_use "requires contract" (vars_of_ltl assume))
    n.assumes;
  List.iter
    (fun guarantee ->
      validate_ltl guarantee;
      reject_ghost_use "ensures contract" (vars_of_ltl guarantee))
    n.guarantees

let node ~(type_decls : Core_syntax.enum_decl list) (n : Kx_ast.node) :
    Verification_model.node_model =
  let sem = Kx_ast.semantics_of_node n in
  let spec = Kx_ast.specification_of_node n in
  let lowered =
    {
    Verification_model.node_name = sem.sem_nname;
    type_decls;
    inputs = List.map lower_vdecl sem.sem_inputs;
    outputs = List.map lower_vdecl sem.sem_outputs;
    locals = List.map lower_vdecl sem.sem_locals;
    ghosts = List.map lower_vdecl sem.sem_ghosts;
    states = sem.sem_states;
    init_state = sem.sem_init_state;
    steps = List.map (step ~type_decls) sem.sem_trans;
    assumes = List.map (ltl ~type_decls) spec.spec_assumes;
    guarantees = List.map (ltl ~type_decls) spec.spec_guarantees;
    state_invariants =
      List.map (lower_state_invariant ~type_decls) spec.spec_invariants_state_rel;
  }
  in
  validate_node lowered;
  Verification_model.prioritize_node_steps lowered

let program ?(type_decls : Kx_core_syntax.enum_decl list = []) (p : Kx_ast.program) :
    Verification_model.program_model =
  let type_decls = List.map lower_enum_decl type_decls in
  validate_unique_type_decls type_decls;
  List.map (node ~type_decls) p
