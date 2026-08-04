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


(* [expr ~(type_decls : Kr_domain_core.Core_syntax.enum_decl list)] implements the internal expr operation. It returns the operation result. *)
let rec expr ~(type_decls : Kr_domain_core.Core_syntax.enum_decl list)
    (source_expr : Kr_lang_core.Kr_lang_core_syntax.expr) : Kr_domain_core.Core_syntax.expr =
  let lowered =
    match source_expr.expr with
    | Kr_lang_core.Kr_lang_core_syntax.ELitInt n -> Kr_domain_core.Core_syntax.ELitInt n
    | Kr_lang_core.Kr_lang_core_syntax.ELitBool b -> Kr_domain_core.Core_syntax.ELitBool b
    | Kr_lang_core.Kr_lang_core_syntax.EVar v -> (
        match Internal.To_model_validation.lookup_constructor type_decls v with
        | Some _ -> Kr_domain_core.Core_syntax.ELitEnum v
        | None -> Kr_domain_core.Core_syntax.EVar v)
    | Kr_lang_core.Kr_lang_core_syntax.EFunCall (fn, args) ->
        Kr_domain_core.Core_syntax.EFunCall (fn, List.map (expr ~type_decls) args)
    | Kr_lang_core.Kr_lang_core_syntax.EBin (op, a, b) ->
        Kr_domain_core.Core_syntax.EBin
          (op, expr ~type_decls a, expr ~type_decls b)
    | Kr_lang_core.Kr_lang_core_syntax.ECmp (op, a, b) ->
        Kr_domain_core.Core_syntax.ECmp
          (op, expr ~type_decls a, expr ~type_decls b)
    | Kr_lang_core.Kr_lang_core_syntax.EUn (op, inner) ->
        Kr_domain_core.Core_syntax.EUn (op, expr ~type_decls inner)
  in
  { Kr_domain_core.Core_syntax.expr = lowered; loc = source_expr.loc }

(* [hexpr ~(type_decls : Kr_domain_core.Core_syntax.enum_decl list)] implements the internal hexpr operation. It returns the operation result. *)
let rec hexpr ~(type_decls : Kr_domain_core.Core_syntax.enum_decl list)
    (source_hexpr : Kr_lang_core.Kr_lang_core_syntax.hexpr) :
    Kr_domain_core.Core_syntax.historical Kr_domain_core.Core_syntax.hexpr =
  let lowered =
    match source_hexpr.hexpr with
    | Kr_lang_core.Kr_lang_core_syntax.HLitInt n -> Kr_domain_core.Core_syntax.HLitInt n
    | Kr_lang_core.Kr_lang_core_syntax.HLitBool b -> Kr_domain_core.Core_syntax.HLitBool b
    | Kr_lang_core.Kr_lang_core_syntax.HVar v -> (
        match Internal.To_model_validation.lookup_constructor type_decls v with
        | Some _ -> Kr_domain_core.Core_syntax.HLitEnum v
        | None -> Kr_domain_core.Core_syntax.HVar v)
    | Kr_lang_core.Kr_lang_core_syntax.HOld inner ->
        Kr_domain_core.Core_syntax.HOld (hexpr ~type_decls inner)
    | Kr_lang_core.Kr_lang_core_syntax.HPreK (v, k) -> Kr_domain_core.Core_syntax.HPreK (v, k)
    | Kr_lang_core.Kr_lang_core_syntax.HPred (id, hs) ->
        Kr_domain_core.Core_syntax.HPred (id, List.map (hexpr ~type_decls) hs)
    | Kr_lang_core.Kr_lang_core_syntax.HFunCall (fn, hs) ->
        Kr_domain_core.Core_syntax.HFunCall (fn, List.map (hexpr ~type_decls) hs)
    | Kr_lang_core.Kr_lang_core_syntax.HBin (op, a, b) ->
        Kr_domain_core.Core_syntax.HBin
          (op, hexpr ~type_decls a, hexpr ~type_decls b)
    | Kr_lang_core.Kr_lang_core_syntax.HCmp (op, a, b) ->
        Kr_domain_core.Core_syntax.HCmp
          (op, hexpr ~type_decls a, hexpr ~type_decls b)
    | Kr_lang_core.Kr_lang_core_syntax.HUn (op, inner) ->
        Kr_domain_core.Core_syntax.HUn (op, hexpr ~type_decls inner)
  in
  { Kr_domain_core.Core_syntax.hexpr = lowered; loc = source_hexpr.loc }

(* [history_free_hexpr ~type_decls source_hexpr] implements the internal history free hexpr operation. It returns the operation result. *)
let history_free_hexpr ~type_decls source_hexpr =
  match
    Kr_domain_core.Core_syntax.history_free_of_historical (hexpr ~type_decls source_hexpr)
  with
  | Some formula -> formula
  | None ->
      invalid_arg
        "history is not allowed in this first-order program context"

(* [ltl ~(type_decls : Kr_domain_core.Core_syntax.enum_decl list)] implements the internal ltl operation. It returns the operation result. *)
let rec ltl ~(type_decls : Kr_domain_core.Core_syntax.enum_decl list)
    (source_ltl : Kr_lang_core.Kr_lang_core_syntax.ltl) : Kr_domain_core.Core_syntax.ltl =
  match source_ltl with
  | Kr_lang_core.Kr_lang_core_syntax.LTrue -> Kr_domain_core.Core_syntax.LTrue
  | Kr_lang_core.Kr_lang_core_syntax.LFalse -> Kr_domain_core.Core_syntax.LFalse
  | Kr_lang_core.Kr_lang_core_syntax.LAtom (h1, r, h2) ->
      Kr_domain_core.Core_syntax.LAtom (hexpr ~type_decls h1, r, hexpr ~type_decls h2)
  | Kr_lang_core.Kr_lang_core_syntax.LNot a -> Kr_domain_core.Core_syntax.LNot (ltl ~type_decls a)
  | Kr_lang_core.Kr_lang_core_syntax.LAnd (a, b) ->
      Kr_domain_core.Core_syntax.LAnd (ltl ~type_decls a, ltl ~type_decls b)
  | Kr_lang_core.Kr_lang_core_syntax.LOr (a, b) ->
      Kr_domain_core.Core_syntax.LOr (ltl ~type_decls a, ltl ~type_decls b)
  | Kr_lang_core.Kr_lang_core_syntax.LImp (a, b) ->
      Kr_domain_core.Core_syntax.LImp (ltl ~type_decls a, ltl ~type_decls b)
  | Kr_lang_core.Kr_lang_core_syntax.LX a -> Kr_domain_core.Core_syntax.LX (ltl ~type_decls a)
  | Kr_lang_core.Kr_lang_core_syntax.LG a -> Kr_domain_core.Core_syntax.LG (ltl ~type_decls a)
  | Kr_lang_core.Kr_lang_core_syntax.LW (a, b) ->
      Kr_domain_core.Core_syntax.LW (ltl ~type_decls a, ltl ~type_decls b)

(* [lower_function_decl ~(type_decls : Kr_domain_core.Core_syntax.enum_decl list)] transforms lower function decl. It returns the transformed representation. *)
let lower_function_decl ~(type_decls : Kr_domain_core.Core_syntax.enum_decl list)
    (f : Kr_lang_core.Kr_lang_core_syntax.pure_function_decl) : Kr_domain_core.Core_syntax.pure_function_decl =
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

(* [lower_state_invariant ~(type_decls : Kr_domain_core.Core_syntax.enum_decl list)] transforms lower state invariant. It returns the transformed representation. *)
let lower_state_invariant ~(type_decls : Kr_domain_core.Core_syntax.enum_decl list)
    (inv : Kr_lang_core.Kr_lang_core_ast.invariant_state_rel) : Kr_domain_core.Verification_model.state_invariant =
  { Kr_domain_core.Verification_model.state = inv.state; formula = hexpr ~type_decls inv.formula }

(* [stmt ~(type_decls : Kr_domain_core.Core_syntax.enum_decl list)] implements the internal stmt operation. It returns the operation result. *)
let rec stmt ~(type_decls : Kr_domain_core.Core_syntax.enum_decl list)
    (source_stmt : Kr_lang_core.Kr_lang_core_ast.stmt) : Kr_domain_core.Core_syntax.stmt =
  let lowered =
    match source_stmt.stmt with
    | Kr_lang_core.Kr_lang_core_ast.SAssign (id, e) -> Kr_domain_core.Core_syntax.SAssign (id, expr ~type_decls e)
    | Kr_lang_core.Kr_lang_core_ast.SAssert h ->
        Kr_domain_core.Core_syntax.SAssert (history_free_hexpr ~type_decls h)
    | Kr_lang_core.Kr_lang_core_ast.SIf (c, t, e) ->
        Kr_domain_core.Core_syntax.SIf
          (expr ~type_decls c, List.map (stmt ~type_decls) t,
           List.map (stmt ~type_decls) e)
    | Kr_lang_core.Kr_lang_core_ast.SWhile (c, invariants, variant, body) ->
        Kr_domain_core.Core_syntax.SWhile
          ( expr ~type_decls c,
            List.map (history_free_hexpr ~type_decls) invariants,
            Option.map (expr ~type_decls) variant,
            List.map (stmt ~type_decls) body )
    | Kr_lang_core.Kr_lang_core_ast.SMatch (e, branches, dflt) ->
        Kr_domain_core.Core_syntax.SMatch
          ( expr ~type_decls e,
            List.map
              (fun (ctor, body) -> (ctor, List.map (stmt ~type_decls) body))
              branches,
            List.map (stmt ~type_decls) dflt )
    | Kr_lang_core.Kr_lang_core_ast.SSkip -> Kr_domain_core.Core_syntax.SSkip
    | Kr_lang_core.Kr_lang_core_ast.SMethodCall (callee, args) ->
        Kr_domain_core.Core_syntax.SMethodCall (callee, List.map (expr ~type_decls) args)
  in
  { Kr_domain_core.Core_syntax.stmt = lowered; loc = source_stmt.loc }

(* [step ~(type_decls : Kr_domain_core.Core_syntax.enum_decl list)] implements the internal step operation. It returns the operation result. *)
let step ~(type_decls : Kr_domain_core.Core_syntax.enum_decl list)
    (source_transition : Kr_lang_core.Kr_lang_core_ast.transition) : Kr_domain_core.Verification_model.program_step =
  {
    Kr_domain_core.Verification_model.src_state = source_transition.src;
    dst_state = source_transition.dst;
    guard_expr = Option.map (expr ~type_decls) source_transition.guard;
    body_stmts = List.map (stmt ~type_decls) source_transition.body;
    elaboration_checks = List.map (hexpr ~type_decls) source_transition.ensures;
  }

(* [lower_method ~(type_decls : Kr_domain_core.Core_syntax.enum_decl list)] transforms lower method. It returns the transformed representation. *)
let lower_method ~(type_decls : Kr_domain_core.Core_syntax.enum_decl list)
    (decl : Kr_lang_core.Kr_lang_core_ast.method_decl) : Kr_domain_core.Core_syntax.method_decl =
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

let node ~(type_decls : Kr_domain_core.Core_syntax.enum_decl list)
    ~(function_decls : Kr_domain_core.Core_syntax.pure_function_decl list) (n : Kr_lang_core.Kr_lang_core_ast.node) :
    Kr_domain_core.Verification_model.node_model =
  let sem = Kr_lang_core.Kr_lang_core_ast.semantics_of_node n in
  let spec = Kr_lang_core.Kr_lang_core_ast.specification_of_node n in
  let lowered =
    {
      Kr_domain_core.Verification_model.node_name = sem.sem_nname;
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
  Internal.To_model_validation.validate_node lowered;
  Kr_domain_core.Verification_model.normalize_node_semantics lowered

let program ?(type_decls : Kr_lang_core.Kr_lang_core_syntax.enum_decl list = [])
    ?(function_decls : Kr_lang_core.Kr_lang_core_syntax.pure_function_decl list = [])
    (p : Kr_lang_core.Kr_lang_core_ast.program) : Kr_domain_core.Verification_model.program_model =
  let function_decls =
    List.map (lower_function_decl ~type_decls) function_decls
  in
  Internal.To_model_validation.validate_unique_type_decls type_decls;
  Internal.To_model_validation.validate_function_decls type_decls function_decls;
  List.map (node ~type_decls ~function_decls) p
