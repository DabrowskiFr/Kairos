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

let rec expr (source_expr : Kx_core_syntax.expr) : Core_syntax.expr =
  let lowered =
    match source_expr.expr with
    | Kx_core_syntax.ELitInt n -> Core_syntax.ELitInt n
    | Kx_core_syntax.ELitBool b -> Core_syntax.ELitBool b
    | Kx_core_syntax.EVar v -> Core_syntax.EVar v
    | Kx_core_syntax.EBin (op, a, b) -> Core_syntax.EBin (lower_binop op, expr a, expr b)
    | Kx_core_syntax.ECmp (op, a, b) -> Core_syntax.ECmp (lower_relop op, expr a, expr b)
    | Kx_core_syntax.EUn (op, inner) -> Core_syntax.EUn (lower_unop op, expr inner)
  in
  { Core_syntax.expr = lowered; loc = Option.map loc source_expr.loc }

let rec hexpr (source_hexpr : Kx_core_syntax.hexpr) : Core_syntax.hexpr =
  let lowered =
    match source_hexpr.hexpr with
    | Kx_core_syntax.HLitInt n -> Core_syntax.HLitInt n
    | Kx_core_syntax.HLitBool b -> Core_syntax.HLitBool b
    | Kx_core_syntax.HVar v -> Core_syntax.HVar v
    | Kx_core_syntax.HPreK (v, k) -> Core_syntax.HPreK (v, k)
    | Kx_core_syntax.HPred (id, hs) -> Core_syntax.HPred (id, List.map hexpr hs)
    | Kx_core_syntax.HBin (op, a, b) -> Core_syntax.HBin (lower_binop op, hexpr a, hexpr b)
    | Kx_core_syntax.HCmp (op, a, b) -> Core_syntax.HCmp (lower_relop op, hexpr a, hexpr b)
    | Kx_core_syntax.HUn (op, inner) -> Core_syntax.HUn (lower_unop op, hexpr inner)
  in
  { Core_syntax.hexpr = lowered; loc = Option.map loc source_hexpr.loc }

let rec ltl (source_ltl : Kx_core_syntax.ltl) : Core_syntax.ltl =
  match source_ltl with
  | Kx_core_syntax.LTrue -> Core_syntax.LTrue
  | Kx_core_syntax.LFalse -> Core_syntax.LFalse
  | Kx_core_syntax.LAtom (h1, r, h2) -> Core_syntax.LAtom (hexpr h1, lower_relop r, hexpr h2)
  | Kx_core_syntax.LNot a -> Core_syntax.LNot (ltl a)
  | Kx_core_syntax.LAnd (a, b) -> Core_syntax.LAnd (ltl a, ltl b)
  | Kx_core_syntax.LOr (a, b) -> Core_syntax.LOr (ltl a, ltl b)
  | Kx_core_syntax.LImp (a, b) -> Core_syntax.LImp (ltl a, ltl b)
  | Kx_core_syntax.LX a -> Core_syntax.LX (ltl a)
  | Kx_core_syntax.LG a -> Core_syntax.LG (ltl a)
  | Kx_core_syntax.LW (a, b) -> Core_syntax.LW (ltl a, ltl b)

let lower_vdecl (v : Kx_core_syntax.vdecl) : Core_syntax.vdecl =
  { vname = v.vname; vty = lower_ty v.vty }

let lower_state_invariant (inv : Kx_ast.invariant_state_rel) : Verification_model.state_invariant =
  { Verification_model.state = inv.state; formula = hexpr inv.formula }

let rec stmt (source_stmt : Kx_ast.stmt) : Core_syntax.stmt =
  let lowered =
    match source_stmt.stmt with
    | Kx_ast.SAssign (id, e) -> Core_syntax.SAssign (id, expr e)
    | Kx_ast.SIf (c, t, e) -> Core_syntax.SIf (expr c, List.map stmt t, List.map stmt e)
    | Kx_ast.SMatch (e, branches, dflt) ->
        Core_syntax.SMatch
          ( expr e,
            List.map (fun (ctor, body) -> (ctor, List.map stmt body)) branches,
            List.map stmt dflt )
    | Kx_ast.SSkip -> Core_syntax.SSkip
    | Kx_ast.SCall (callee, args, outs) -> Core_syntax.SCall (callee, List.map expr args, outs)
  in
  { Core_syntax.stmt = lowered; loc = Option.map loc source_stmt.loc }

let step (source_transition : Kx_ast.transition) : Verification_model.program_step =
  {
    Verification_model.src_state = source_transition.src;
    dst_state = source_transition.dst;
    guard_expr = Option.map expr source_transition.guard;
    body_stmts = List.map stmt source_transition.body;
  }

let node (n : Kx_ast.node) : Verification_model.node_model =
  let sem = Kx_ast.semantics_of_node n in
  let spec = Kx_ast.specification_of_node n in
  {
    Verification_model.node_name = sem.sem_nname;
    inputs = List.map lower_vdecl sem.sem_inputs;
    outputs = List.map lower_vdecl sem.sem_outputs;
    locals = List.map lower_vdecl sem.sem_locals;
    states = sem.sem_states;
    init_state = sem.sem_init_state;
    steps = List.map step sem.sem_trans;
    assumes = List.map ltl spec.spec_assumes;
    guarantees = List.map ltl spec.spec_guarantees;
    state_invariants = List.map lower_state_invariant spec.spec_invariants_state_rel;
  }
  |> Verification_model.prioritize_node_steps

let program (p : Kx_ast.program) : Verification_model.program_model =
  List.map node p
