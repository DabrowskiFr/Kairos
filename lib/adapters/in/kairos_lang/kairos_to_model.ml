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

module Validation = Kairos_to_model_validation

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

let rec expr ~(type_decls : Core_syntax.enum_decl list)
    (source_expr : Kx_core_syntax.expr) : Core_syntax.expr =
  let lowered =
    match source_expr.expr with
    | Kx_core_syntax.ELitInt n -> Core_syntax.ELitInt n
    | Kx_core_syntax.ELitBool b -> Core_syntax.ELitBool b
    | Kx_core_syntax.EVar v -> (
        match Validation.lookup_constructor type_decls v with
        | Some _ -> Core_syntax.ELitEnum v
        | None -> Core_syntax.EVar v)
    | Kx_core_syntax.EFunCall (fn, args) ->
        Core_syntax.EFunCall (fn, List.map (expr ~type_decls) args)
    | Kx_core_syntax.EBin (op, a, b) ->
        Core_syntax.EBin
          (lower_binop op, expr ~type_decls a, expr ~type_decls b)
    | Kx_core_syntax.ECmp (op, a, b) ->
        Core_syntax.ECmp
          (lower_relop op, expr ~type_decls a, expr ~type_decls b)
    | Kx_core_syntax.EUn (op, inner) ->
        Core_syntax.EUn (lower_unop op, expr ~type_decls inner)
  in
  { Core_syntax.expr = lowered; loc = Option.map loc source_expr.loc }

let rec hexpr ~(type_decls : Core_syntax.enum_decl list)
    (source_hexpr : Kx_core_syntax.hexpr) :
    Core_syntax.historical Core_syntax.hexpr =
  let lowered =
    match source_hexpr.hexpr with
    | Kx_core_syntax.HLitInt n -> Core_syntax.HLitInt n
    | Kx_core_syntax.HLitBool b -> Core_syntax.HLitBool b
    | Kx_core_syntax.HVar v -> (
        match Validation.lookup_constructor type_decls v with
        | Some _ -> Core_syntax.HLitEnum v
        | None -> Core_syntax.HVar v)
    | Kx_core_syntax.HPreK (v, k) -> Core_syntax.HPreK (v, k)
    | Kx_core_syntax.HPred (id, hs) ->
        Core_syntax.HPred (id, List.map (hexpr ~type_decls) hs)
    | Kx_core_syntax.HFunCall (fn, hs) ->
        Core_syntax.HFunCall (fn, List.map (hexpr ~type_decls) hs)
    | Kx_core_syntax.HBin (op, a, b) ->
        Core_syntax.HBin
          (lower_binop op, hexpr ~type_decls a, hexpr ~type_decls b)
    | Kx_core_syntax.HCmp (op, a, b) ->
        Core_syntax.HCmp
          (lower_relop op, hexpr ~type_decls a, hexpr ~type_decls b)
    | Kx_core_syntax.HUn (op, inner) ->
        Core_syntax.HUn (lower_unop op, hexpr ~type_decls inner)
  in
  { Core_syntax.hexpr = lowered; loc = Option.map loc source_hexpr.loc }

let history_free_hexpr ~type_decls source_hexpr =
  match
    Core_syntax.history_free_of_historical (hexpr ~type_decls source_hexpr)
  with
  | Some formula -> formula
  | None ->
      invalid_arg
        "history is not allowed in this first-order program context"

let rec ltl ~(type_decls : Core_syntax.enum_decl list)
    (source_ltl : Kx_core_syntax.ltl) : Core_syntax.ltl =
  match source_ltl with
  | Kx_core_syntax.LTrue -> Core_syntax.LTrue
  | Kx_core_syntax.LFalse -> Core_syntax.LFalse
  | Kx_core_syntax.LAtom (h1, r, h2) ->
      Core_syntax.LAtom (hexpr ~type_decls h1, lower_relop r, hexpr ~type_decls h2)
  | Kx_core_syntax.LNot a -> Core_syntax.LNot (ltl ~type_decls a)
  | Kx_core_syntax.LAnd (a, b) ->
      Core_syntax.LAnd (ltl ~type_decls a, ltl ~type_decls b)
  | Kx_core_syntax.LOr (a, b) ->
      Core_syntax.LOr (ltl ~type_decls a, ltl ~type_decls b)
  | Kx_core_syntax.LImp (a, b) ->
      Core_syntax.LImp (ltl ~type_decls a, ltl ~type_decls b)
  | Kx_core_syntax.LX a -> Core_syntax.LX (ltl ~type_decls a)
  | Kx_core_syntax.LG a -> Core_syntax.LG (ltl ~type_decls a)
  | Kx_core_syntax.LW (a, b) ->
      Core_syntax.LW (ltl ~type_decls a, ltl ~type_decls b)

let lower_vdecl (v : Kx_core_syntax.vdecl) : Core_syntax.vdecl =
  { vname = v.vname; vty = lower_ty v.vty }

let lower_function_decl ~(type_decls : Core_syntax.enum_decl list)
    (f : Kx_core_syntax.pure_function_decl) : Core_syntax.pure_function_decl =
  {
    function_name = f.function_name;
    function_params = List.map lower_vdecl f.function_params;
    function_return = lower_ty f.function_return;
    function_requires =
      List.map (history_free_hexpr ~type_decls) f.function_requires;
    function_ensures =
      List.map (history_free_hexpr ~type_decls) f.function_ensures;
    function_body = expr ~type_decls f.function_body;
  }

let lower_state_invariant ~(type_decls : Core_syntax.enum_decl list)
    (inv : Kx_ast.invariant_state_rel) : Verification_model.state_invariant =
  { Verification_model.state = inv.state; formula = hexpr ~type_decls inv.formula }

let rec stmt ~(type_decls : Core_syntax.enum_decl list)
    (source_stmt : Kx_ast.stmt) : Core_syntax.stmt =
  let lowered =
    match source_stmt.stmt with
    | Kx_ast.SAssign (id, e) -> Core_syntax.SAssign (id, expr ~type_decls e)
    | Kx_ast.SAssert h ->
        Core_syntax.SAssert (history_free_hexpr ~type_decls h)
    | Kx_ast.SIf (c, t, e) ->
        Core_syntax.SIf
          (expr ~type_decls c, List.map (stmt ~type_decls) t,
           List.map (stmt ~type_decls) e)
    | Kx_ast.SWhile (c, invariants, variant, body) ->
        Core_syntax.SWhile
          ( expr ~type_decls c,
            List.map (history_free_hexpr ~type_decls) invariants,
            Option.map (expr ~type_decls) variant,
            List.map (stmt ~type_decls) body )
    | Kx_ast.SMatch (e, branches, dflt) ->
        Core_syntax.SMatch
          ( expr ~type_decls e,
            List.map
              (fun (ctor, body) -> (ctor, List.map (stmt ~type_decls) body))
              branches,
            List.map (stmt ~type_decls) dflt )
    | Kx_ast.SSkip -> Core_syntax.SSkip
    | Kx_ast.SCall (callee, args, outs) ->
        Core_syntax.SCall (callee, List.map (expr ~type_decls) args, outs)
  in
  { Core_syntax.stmt = lowered; loc = Option.map loc source_stmt.loc }

let step ~(type_decls : Core_syntax.enum_decl list)
    (source_transition : Kx_ast.transition) : Verification_model.program_step =
  {
    Verification_model.src_state = source_transition.src;
    dst_state = source_transition.dst;
    guard_expr = Option.map (expr ~type_decls) source_transition.guard;
    body_stmts = List.map (stmt ~type_decls) source_transition.body;
    elaboration_checks = List.map (hexpr ~type_decls) source_transition.ensures;
  }

let node ~(type_decls : Core_syntax.enum_decl list)
    ~(function_decls : Core_syntax.pure_function_decl list) (n : Kx_ast.node) :
    Verification_model.node_model =
  let sem = Kx_ast.semantics_of_node n in
  let spec = Kx_ast.specification_of_node n in
  let lowered =
    {
      Verification_model.node_name = sem.sem_nname;
      type_decls;
      function_decls;
      inputs = List.map lower_vdecl sem.sem_inputs;
      outputs = List.map lower_vdecl sem.sem_outputs;
      locals = List.map lower_vdecl sem.sem_locals;
      ghosts = List.map lower_vdecl sem.sem_ghosts;
      public_ghosts = sem.sem_public_ghosts;
      states = sem.sem_states;
      init_state = sem.sem_init_state;
      steps = List.map (step ~type_decls) sem.sem_trans;
      assumes = List.map (ltl ~type_decls) spec.spec_assumes;
      guarantees = List.map (ltl ~type_decls) spec.spec_guarantees;
      state_invariants =
        List.map (lower_state_invariant ~type_decls)
          spec.spec_invariants_state_rel;
    }
  in
  Validation.validate_node lowered;
  Verification_model.normalize_node_semantics lowered

let program ?(type_decls : Kx_core_syntax.enum_decl list = [])
    ?(function_decls : Kx_core_syntax.pure_function_decl list = [])
    (p : Kx_ast.program) : Verification_model.program_model =
  let type_decls = List.map lower_enum_decl type_decls in
  let function_decls =
    List.map (lower_function_decl ~type_decls) function_decls
  in
  Validation.validate_unique_type_decls type_decls;
  Validation.validate_function_decls type_decls function_decls;
  List.map (node ~type_decls ~function_decls) p
