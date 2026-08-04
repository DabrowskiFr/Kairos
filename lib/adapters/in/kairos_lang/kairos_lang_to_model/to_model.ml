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


(* [expr ~(type_decls : Core_syntax.enum_decl list)] implements the internal expr operation. It returns the operation result. *)
let rec expr ~(type_decls : Core_syntax.enum_decl list)
    (source_expr : Core.Syntax.expr) : Core_syntax.expr =
  let lowered =
    match source_expr.expr with
    | Core.Syntax.ELitInt n -> Core_syntax.ELitInt n
    | Core.Syntax.ELitBool b -> Core_syntax.ELitBool b
    | Core.Syntax.EVar v -> (
        match To_model_validation.lookup_constructor type_decls v with
        | Some _ -> Core_syntax.ELitEnum v
        | None -> Core_syntax.EVar v)
    | Core.Syntax.EFunCall (fn, args) ->
        Core_syntax.EFunCall (fn, List.map (expr ~type_decls) args)
    | Core.Syntax.EBin (op, a, b) ->
        Core_syntax.EBin
          (op, expr ~type_decls a, expr ~type_decls b)
    | Core.Syntax.ECmp (op, a, b) ->
        Core_syntax.ECmp
          (op, expr ~type_decls a, expr ~type_decls b)
    | Core.Syntax.EUn (op, inner) ->
        Core_syntax.EUn (op, expr ~type_decls inner)
  in
  { Core_syntax.expr = lowered; loc = source_expr.loc }

(* [hexpr ~(type_decls : Core_syntax.enum_decl list)] implements the internal hexpr operation. It returns the operation result. *)
let rec hexpr ~(type_decls : Core_syntax.enum_decl list)
    (source_hexpr : Core.Syntax.hexpr) :
    Core_syntax.historical Core_syntax.hexpr =
  let lowered =
    match source_hexpr.hexpr with
    | Core.Syntax.HLitInt n -> Core_syntax.HLitInt n
    | Core.Syntax.HLitBool b -> Core_syntax.HLitBool b
    | Core.Syntax.HVar v -> (
        match To_model_validation.lookup_constructor type_decls v with
        | Some _ -> Core_syntax.HLitEnum v
        | None -> Core_syntax.HVar v)
    | Core.Syntax.HOld inner ->
        Core_syntax.HOld (hexpr ~type_decls inner)
    | Core.Syntax.HPreK (v, k) -> Core_syntax.HPreK (v, k)
    | Core.Syntax.HPred (id, hs) ->
        Core_syntax.HPred (id, List.map (hexpr ~type_decls) hs)
    | Core.Syntax.HFunCall (fn, hs) ->
        Core_syntax.HFunCall (fn, List.map (hexpr ~type_decls) hs)
    | Core.Syntax.HBin (op, a, b) ->
        Core_syntax.HBin
          (op, hexpr ~type_decls a, hexpr ~type_decls b)
    | Core.Syntax.HCmp (op, a, b) ->
        Core_syntax.HCmp
          (op, hexpr ~type_decls a, hexpr ~type_decls b)
    | Core.Syntax.HUn (op, inner) ->
        Core_syntax.HUn (op, hexpr ~type_decls inner)
  in
  { Core_syntax.hexpr = lowered; loc = source_hexpr.loc }

(* [history_free_hexpr ~type_decls source_hexpr] implements the internal history free hexpr operation. It returns the operation result. *)
let history_free_hexpr ~type_decls source_hexpr =
  match
    Core_syntax.history_free_of_historical (hexpr ~type_decls source_hexpr)
  with
  | Some formula -> formula
  | None ->
      invalid_arg
        "history is not allowed in this first-order program context"

(* [ltl ~(type_decls : Core_syntax.enum_decl list)] implements the internal ltl operation. It returns the operation result. *)
let rec ltl ~(type_decls : Core_syntax.enum_decl list)
    (source_ltl : Core.Syntax.ltl) : Core_syntax.ltl =
  match source_ltl with
  | Core.Syntax.LTrue -> Core_syntax.LTrue
  | Core.Syntax.LFalse -> Core_syntax.LFalse
  | Core.Syntax.LAtom (h1, r, h2) ->
      Core_syntax.LAtom (hexpr ~type_decls h1, r, hexpr ~type_decls h2)
  | Core.Syntax.LNot a -> Core_syntax.LNot (ltl ~type_decls a)
  | Core.Syntax.LAnd (a, b) ->
      Core_syntax.LAnd (ltl ~type_decls a, ltl ~type_decls b)
  | Core.Syntax.LOr (a, b) ->
      Core_syntax.LOr (ltl ~type_decls a, ltl ~type_decls b)
  | Core.Syntax.LImp (a, b) ->
      Core_syntax.LImp (ltl ~type_decls a, ltl ~type_decls b)
  | Core.Syntax.LX a -> Core_syntax.LX (ltl ~type_decls a)
  | Core.Syntax.LG a -> Core_syntax.LG (ltl ~type_decls a)
  | Core.Syntax.LW (a, b) ->
      Core_syntax.LW (ltl ~type_decls a, ltl ~type_decls b)

(* [lower_function_decl ~(type_decls : Core_syntax.enum_decl list)] transforms lower function decl. It returns the transformed representation. *)
let lower_function_decl ~(type_decls : Core_syntax.enum_decl list)
    (f : Core.Syntax.pure_function_decl) : Core_syntax.pure_function_decl =
  {
    function_name = f.function_name;
    function_params = f.function_params;
    function_return = f.function_return;
    function_requires =
      List.map (history_free_hexpr ~type_decls) f.function_requires;
    function_ensures =
      List.map (history_free_hexpr ~type_decls) f.function_ensures;
    function_body = expr ~type_decls f.function_body;
  }

(* [lower_state_invariant ~(type_decls : Core_syntax.enum_decl list)] transforms lower state invariant. It returns the transformed representation. *)
let lower_state_invariant ~(type_decls : Core_syntax.enum_decl list)
    (inv : Core.Ast.invariant_state_rel) : Verification_model.state_invariant =
  { Verification_model.state = inv.state; formula = hexpr ~type_decls inv.formula }

(* [stmt ~(type_decls : Core_syntax.enum_decl list)] implements the internal stmt operation. It returns the operation result. *)
let rec stmt ~(type_decls : Core_syntax.enum_decl list)
    (source_stmt : Core.Ast.stmt) : Core_syntax.stmt =
  let lowered =
    match source_stmt.stmt with
    | Core.Ast.SAssign (id, e) -> Core_syntax.SAssign (id, expr ~type_decls e)
    | Core.Ast.SAssert h ->
        Core_syntax.SAssert (history_free_hexpr ~type_decls h)
    | Core.Ast.SIf (c, t, e) ->
        Core_syntax.SIf
          (expr ~type_decls c, List.map (stmt ~type_decls) t,
           List.map (stmt ~type_decls) e)
    | Core.Ast.SWhile (c, invariants, variant, body) ->
        Core_syntax.SWhile
          ( expr ~type_decls c,
            List.map (history_free_hexpr ~type_decls) invariants,
            Option.map (expr ~type_decls) variant,
            List.map (stmt ~type_decls) body )
    | Core.Ast.SMatch (e, branches, dflt) ->
        Core_syntax.SMatch
          ( expr ~type_decls e,
            List.map
              (fun (ctor, body) -> (ctor, List.map (stmt ~type_decls) body))
              branches,
            List.map (stmt ~type_decls) dflt )
    | Core.Ast.SSkip -> Core_syntax.SSkip
    | Core.Ast.SMethodCall (callee, args) ->
        Core_syntax.SMethodCall (callee, List.map (expr ~type_decls) args)
  in
  { Core_syntax.stmt = lowered; loc = source_stmt.loc }

(* [step ~(type_decls : Core_syntax.enum_decl list)] implements the internal step operation. It returns the operation result. *)
let step ~(type_decls : Core_syntax.enum_decl list)
    (source_transition : Core.Ast.transition) : Verification_model.program_step =
  {
    Verification_model.src_state = source_transition.src;
    dst_state = source_transition.dst;
    guard_expr = Option.map (expr ~type_decls) source_transition.guard;
    body_stmts = List.map (stmt ~type_decls) source_transition.body;
    elaboration_checks = List.map (hexpr ~type_decls) source_transition.ensures;
  }

(* [lower_method ~(type_decls : Core_syntax.enum_decl list)] transforms lower method. It returns the transformed representation. *)
let lower_method ~(type_decls : Core_syntax.enum_decl list)
    (decl : Core.Ast.method_decl) : Core_syntax.method_decl =
  {
    method_name = decl.method_name;
    method_params = decl.method_params;
    method_requires =
      List.map (history_free_hexpr ~type_decls) decl.method_requires;
    method_ensures =
      List.map (history_free_hexpr ~type_decls) decl.method_ensures;
    method_body = List.map (stmt ~type_decls) decl.method_body;
    method_reads = decl.method_reads;
    method_writes = decl.method_writes;
  }

let node ~(type_decls : Core_syntax.enum_decl list)
    ~(function_decls : Core_syntax.pure_function_decl list) (n : Core.Ast.node) :
    Verification_model.node_model =
  let sem = Core.Ast.semantics_of_node n in
  let spec = Core.Ast.specification_of_node n in
  let lowered =
    {
      Verification_model.node_name = sem.sem_nname;
      type_decls;
      function_decls;
      methods = List.map (lower_method ~type_decls) sem.sem_methods;
      inputs = sem.sem_inputs;
      outputs = sem.sem_outputs;
      locals = sem.sem_locals;
      ghosts = sem.sem_ghosts;
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
  To_model_validation.validate_node lowered;
  Verification_model.normalize_node_semantics lowered

let program ?(type_decls : Core.Syntax.enum_decl list = [])
    ?(function_decls : Core.Syntax.pure_function_decl list = [])
    (p : Core.Ast.program) : Verification_model.program_model =
  let function_decls =
    List.map (lower_function_decl ~type_decls) function_decls
  in
  To_model_validation.validate_unique_type_decls type_decls;
  To_model_validation.validate_function_decls type_decls function_decls;
  List.map (node ~type_decls ~function_decls) p
