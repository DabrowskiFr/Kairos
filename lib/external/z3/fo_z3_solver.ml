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
open Ast
open Pretty

let mk_expr expr = { expr; loc = None }
let ( let* ) = Option.bind

type smt_sort = SInt | SBool

type z3_env = {
  ctx : Z3.context;
  vars : (ident, smt_sort) Hashtbl.t;
  z3_vars : (string, ident) Hashtbl.t;
  z3_preds : (string, ident) Hashtbl.t;
  z3_preks : (string, int) Hashtbl.t;
}

let fo_simplifier_forced_off () =
  match Sys.getenv_opt "KAIROS_FO_SIMPLIFIER" with
  | Some "off" -> true
  | _ -> false

let rec sanitize_ident (s : string) : string =
  let buf = Buffer.create (String.length s + 8) in
  String.iter
    (fun c ->
      match c with
      | 'a' .. 'z' | 'A' .. 'Z' | '0' .. '9' | '_' -> Buffer.add_char buf c
      | _ -> Buffer.add_char buf '_')
    s;
  let out = Buffer.contents buf in
  if out = "" then "__kairos"
  else
    match out.[0] with
    | '0' .. '9' -> "__" ^ out
    | _ -> out

let string_of_sort = function SInt -> "Int" | SBool -> "Bool"

let rec infer_expr_sort (vars : (ident, smt_sort) Hashtbl.t) (e : expr) : smt_sort option =
  let unify_var v s =
    match Hashtbl.find_opt vars v with
    | None ->
        Hashtbl.add vars v s;
        Some s
    | Some s' -> Some s'
  in
  match e.expr with
  | ELitInt _ -> Some SInt
  | ELitBool _ -> Some SBool
  | EVar v -> Hashtbl.find_opt vars v
  | EUn (Neg, a) ->
      let _ = infer_expr_sort vars a in
      Some SInt
  | EUn (Not, a) ->
      let _ = infer_expr_sort vars a in
      Some SBool
  | EBin (op, a, b) ->
      let _ = infer_expr_sort vars a in
      let _ = infer_expr_sort vars b in
      begin
        match op with
        | Add | Sub | Mul | Div -> Some SInt
        | And | Or -> Some SBool
      end
  | ECmp (_, a, b) -> begin
      let sa = infer_expr_sort vars a in
      let sb = infer_expr_sort vars b in
      let operand_sort =
        match (sa, sb) with Some s, _ | _, Some s -> s | None, None -> SInt
      in
      (match a.expr with EVar v -> ignore (unify_var v operand_sort) | _ -> ());
      (match b.expr with EVar v -> ignore (unify_var v operand_sort) | _ -> ());
      Some SBool
    end

let rec infer_hexpr_sort vars (h : hexpr) =
  match h.hexpr with
  | HLitInt _ -> Some SInt
  | HLitBool _ -> Some SBool
  | HVar v -> Hashtbl.find_opt vars v
  | HPreK (v, _) -> Hashtbl.find_opt vars v
  | HPred (_, hs) ->
      List.iter (fun x -> ignore (infer_hexpr_sort vars x)) hs;
      Some SBool
  | HUn (Neg, inner) ->
      let _ = infer_hexpr_sort vars inner in
      Some SInt
  | HUn (Not, inner) ->
      let _ = infer_hexpr_sort vars inner in
      Some SBool
  | HBin (op, a, b) ->
      let _ = infer_hexpr_sort vars a in
      let _ = infer_hexpr_sort vars b in
      begin
        match op with
        | Add | Sub | Mul | Div -> Some SInt
        | And | Or -> Some SBool
      end
  | HCmp (RLt, a, b) | HCmp (RLe, a, b) | HCmp (RGt, a, b) | HCmp (RGe, a, b) ->
      let _ = infer_hexpr_sort vars a in
      let _ = infer_hexpr_sort vars b in
      Some SBool
  | HCmp (REq, a, b) | HCmp (RNeq, a, b) -> begin
      let sa = infer_hexpr_sort vars a in
      let sb = infer_hexpr_sort vars b in
      match (sa, sb) with Some s, _ | _, Some s -> Some s | None, None -> Some SInt
    end

let infer_atom_sorts (f : fo_atom) (vars : (ident, smt_sort) Hashtbl.t) : unit =
  let var_of_hexpr (h : hexpr) =
    match h.hexpr with HVar v | HPreK (v, _) -> Some v | _ -> None
  in
  match f with
  | FRel (h1, r, h2) -> begin
      match r with
      | RLt | RLe | RGt | RGe ->
          let _ = infer_hexpr_sort vars h1 in
          let _ = infer_hexpr_sort vars h2 in
          ()
      | REq | RNeq ->
          let s1 = infer_hexpr_sort vars h1 in
          let s2 = infer_hexpr_sort vars h2 in
          let s =
            match (s1, s2) with Some s, _ | _, Some s -> s | None, None -> SInt
          in
          Option.iter (fun v -> Hashtbl.replace vars v s) (var_of_hexpr h1);
          Option.iter (fun v -> Hashtbl.replace vars v s) (var_of_hexpr h2)
    end
  | FPred (_, hs) -> List.iter (fun h -> ignore (infer_hexpr_sort vars h)) hs

let infer_formula_sorts_fo (f : Core_syntax.hexpr) : (ident, smt_sort) Hashtbl.t =
  let vars = Hashtbl.create 32 in
  ignore (infer_hexpr_sort vars f);
  vars

let make_z3_env (f : Core_syntax.hexpr) : z3_env =
  let ctx = Z3.mk_context [] in
  let vars = infer_formula_sorts_fo f in
  { ctx; vars; z3_vars = Hashtbl.create 32; z3_preds = Hashtbl.create 16; z3_preks = Hashtbl.create 16 }

let smt_var_name (v : ident) : string = "__v_" ^ sanitize_ident v
let smt_pred_name (id : ident) (arity : int) : string = "__p_" ^ sanitize_ident id ^ "_" ^ string_of_int arity

let smt_prek_name (k : int) (sort : smt_sort) : string =
  "__pre_" ^ string_of_int k ^ "_" ^ String.lowercase_ascii (string_of_sort sort)

let z3_sort (env : z3_env) = function
  | SInt -> Z3.Arithmetic.Integer.mk_sort env.ctx
  | SBool -> Z3.Boolean.mk_sort env.ctx

let rec z3_of_expr (env : z3_env) (e : expr) : Z3.Expr.expr * smt_sort =
  match e.expr with
  | ELitInt i -> (Z3.Arithmetic.Integer.mk_numeral_i env.ctx i, SInt)
  | ELitBool b -> (Z3.Boolean.mk_val env.ctx b, SBool)
  | EVar v ->
      let sort = Hashtbl.find_opt env.vars v |> Option.value ~default:SInt in
      let name = smt_var_name v in
      Hashtbl.replace env.z3_vars name v;
      (Z3.Expr.mk_const_s env.ctx name (z3_sort env sort), sort)
  | EUn (Neg, a) ->
      let a, _ = z3_of_expr env a in
      (Z3.Arithmetic.mk_unary_minus env.ctx a, SInt)
  | EUn (Not, a) ->
      let a, _ = z3_of_expr env a in
      (Z3.Boolean.mk_not env.ctx a, SBool)
  | EBin (op, a, b) ->
      let a, _ = z3_of_expr env a in
      let b, _ = z3_of_expr env b in
      begin
        match op with
        | Add -> (Z3.Arithmetic.mk_add env.ctx [ a; b ], SInt)
        | Sub -> (Z3.Arithmetic.mk_sub env.ctx [ a; b ], SInt)
        | Mul -> (Z3.Arithmetic.mk_mul env.ctx [ a; b ], SInt)
        | Div -> (Z3.Arithmetic.mk_div env.ctx a b, SInt)
        | And -> (Z3.Boolean.mk_and env.ctx [ a; b ], SBool)
        | Or -> (Z3.Boolean.mk_or env.ctx [ a; b ], SBool)
      end
  | ECmp (REq, a, b) ->
      let a, _ = z3_of_expr env a in
      let b, _ = z3_of_expr env b in
      (Z3.Boolean.mk_eq env.ctx a b, SBool)
  | ECmp (RNeq, a, b) ->
      let a, _ = z3_of_expr env a in
      let b, _ = z3_of_expr env b in
      (Z3.Boolean.mk_not env.ctx (Z3.Boolean.mk_eq env.ctx a b), SBool)
  | ECmp (RLt, a, b) ->
      let a, _ = z3_of_expr env a in
      let b, _ = z3_of_expr env b in
      (Z3.Arithmetic.mk_lt env.ctx a b, SBool)
  | ECmp (RLe, a, b) ->
      let a, _ = z3_of_expr env a in
      let b, _ = z3_of_expr env b in
      (Z3.Arithmetic.mk_le env.ctx a b, SBool)
  | ECmp (RGt, a, b) ->
      let a, _ = z3_of_expr env a in
      let b, _ = z3_of_expr env b in
      (Z3.Arithmetic.mk_gt env.ctx a b, SBool)
  | ECmp (RGe, a, b) ->
      let a, _ = z3_of_expr env a in
      let b, _ = z3_of_expr env b in
      (Z3.Arithmetic.mk_ge env.ctx a b, SBool)

let rec z3_of_hexpr (env : z3_env) (h : hexpr) : Z3.Expr.expr * smt_sort =
  match h.hexpr with
  | HLitInt i -> (Z3.Arithmetic.Integer.mk_numeral_i env.ctx i, SInt)
  | HLitBool b -> (Z3.Boolean.mk_val env.ctx b, SBool)
  | HVar v -> z3_of_expr env (mk_expr (EVar v))
  | HPreK (v, k) ->
      let arg, sort = z3_of_expr env (mk_expr (EVar v)) in
      let name = smt_prek_name k sort in
      let fd = Z3.FuncDecl.mk_func_decl_s env.ctx name [ z3_sort env sort ] (z3_sort env sort) in
      Hashtbl.replace env.z3_preks name k;
      (Z3.Expr.mk_app env.ctx fd [ arg ], sort)
  | HPred (id, hs) ->
      let args = List.map (z3_of_hexpr env) hs in
      let sorts = List.map (fun (_, s) -> z3_sort env s) args in
      let name = smt_pred_name id (List.length hs) in
      let fd = Z3.FuncDecl.mk_func_decl_s env.ctx name sorts (Z3.Boolean.mk_sort env.ctx) in
      Hashtbl.replace env.z3_preds name id;
      (Z3.Expr.mk_app env.ctx fd (List.map fst args), SBool)
  | HUn (Neg, inner) ->
      let a, _ = z3_of_hexpr env inner in
      (Z3.Arithmetic.mk_unary_minus env.ctx a, SInt)
  | HUn (Not, inner) ->
      let a, _ = z3_of_hexpr env inner in
      (Z3.Boolean.mk_not env.ctx a, SBool)
  | HBin (op, a, b) ->
      let a, _ = z3_of_hexpr env a in
      let b, _ = z3_of_hexpr env b in
      begin
        match op with
        | Add -> (Z3.Arithmetic.mk_add env.ctx [ a; b ], SInt)
        | Sub -> (Z3.Arithmetic.mk_sub env.ctx [ a; b ], SInt)
        | Mul -> (Z3.Arithmetic.mk_mul env.ctx [ a; b ], SInt)
        | Div -> (Z3.Arithmetic.mk_div env.ctx a b, SInt)
        | And -> (Z3.Boolean.mk_and env.ctx [ a; b ], SBool)
        | Or -> (Z3.Boolean.mk_or env.ctx [ a; b ], SBool)
      end
  | HCmp (REq, a, b) ->
      let a, _ = z3_of_hexpr env a in
      let b, _ = z3_of_hexpr env b in
      (Z3.Boolean.mk_eq env.ctx a b, SBool)
  | HCmp (RNeq, a, b) ->
      let a, _ = z3_of_hexpr env a in
      let b, _ = z3_of_hexpr env b in
      (Z3.Boolean.mk_not env.ctx (Z3.Boolean.mk_eq env.ctx a b), SBool)
  | HCmp (RLt, a, b) ->
      let a, _ = z3_of_hexpr env a in
      let b, _ = z3_of_hexpr env b in
      (Z3.Arithmetic.mk_lt env.ctx a b, SBool)
  | HCmp (RLe, a, b) ->
      let a, _ = z3_of_hexpr env a in
      let b, _ = z3_of_hexpr env b in
      (Z3.Arithmetic.mk_le env.ctx a b, SBool)
  | HCmp (RGt, a, b) ->
      let a, _ = z3_of_hexpr env a in
      let b, _ = z3_of_hexpr env b in
      (Z3.Arithmetic.mk_gt env.ctx a b, SBool)
  | HCmp (RGe, a, b) ->
      let a, _ = z3_of_hexpr env a in
      let b, _ = z3_of_hexpr env b in
      (Z3.Arithmetic.mk_ge env.ctx a b, SBool)

let z3_of_fo_atom (env : z3_env) = function
  | FRel (h1, REq, h2) ->
      let a, _ = z3_of_hexpr env h1 in
      let b, _ = z3_of_hexpr env h2 in
      Z3.Boolean.mk_eq env.ctx a b
  | FRel (h1, RNeq, h2) ->
      let a, _ = z3_of_hexpr env h1 in
      let b, _ = z3_of_hexpr env h2 in
      Z3.Boolean.mk_not env.ctx (Z3.Boolean.mk_eq env.ctx a b)
  | FRel (h1, RLt, h2) ->
      let a, _ = z3_of_hexpr env h1 in
      let b, _ = z3_of_hexpr env h2 in
      Z3.Arithmetic.mk_lt env.ctx a b
  | FRel (h1, RLe, h2) ->
      let a, _ = z3_of_hexpr env h1 in
      let b, _ = z3_of_hexpr env h2 in
      Z3.Arithmetic.mk_le env.ctx a b
  | FRel (h1, RGt, h2) ->
      let a, _ = z3_of_hexpr env h1 in
      let b, _ = z3_of_hexpr env h2 in
      Z3.Arithmetic.mk_gt env.ctx a b
  | FRel (h1, RGe, h2) ->
      let a, _ = z3_of_hexpr env h1 in
      let b, _ = z3_of_hexpr env h2 in
      Z3.Arithmetic.mk_ge env.ctx a b
  | FPred (id, hs) ->
      let args = List.map (z3_of_hexpr env) hs in
      let sorts = List.map (fun (_, s) -> z3_sort env s) args in
      let name = smt_pred_name id (List.length hs) in
      let fd = Z3.FuncDecl.mk_func_decl_s env.ctx name sorts (Z3.Boolean.mk_sort env.ctx) in
      Hashtbl.replace env.z3_preds name id;
      Z3.Expr.mk_app env.ctx fd (List.map fst args)

let z3_of_fo (env : z3_env) (f : Core_syntax.hexpr) : Z3.Expr.expr =
  fst (z3_of_hexpr env f)

let func_name (e : Z3.Expr.expr) : string =
  Z3.Expr.get_func_decl e |> Z3.FuncDecl.get_name |> Z3.Symbol.get_string

let rebuild_and = function
  | [] -> Core_syntax_builders.mk_hbool true
  | [ x ] -> x
  | x :: xs -> List.fold_left Core_syntax_builders.mk_hand x xs

let rebuild_or = function
  | [] -> Core_syntax_builders.mk_hbool false
  | [ x ] -> x
  | x :: xs -> List.fold_left Core_syntax_builders.mk_hor x xs

let is_literal_expr (e : expr) =
  match e.expr with ELitInt _ | ELitBool _ -> true | _ -> false

let is_const_hexpr (h : hexpr) =
  match h.hexpr with HLitInt _ | HLitBool _ -> true | _ -> false

let flip_relop = function
  | REq -> REq
  | RNeq -> RNeq
  | RLt -> RGt
  | RLe -> RGe
  | RGt -> RLt
  | RGe -> RLe

let normalize_rel (h1 : hexpr) (r : relop) (h2 : hexpr) : hexpr * relop * hexpr =
  match (is_const_hexpr h1, is_const_hexpr h2) with
  | true, false -> (h2, flip_relop r, h1)
  | _ -> (h1, r, h2)

let rec fo_of_z3_expr (env : z3_env) (e : Z3.Expr.expr) : expr option =
  if Z3.Boolean.is_true e then Some (mk_expr (ELitBool true))
  else if Z3.Boolean.is_false e then Some (mk_expr (ELitBool false))
  else if Z3.Arithmetic.is_int_numeral e then
    Some (mk_expr (ELitInt (int_of_string (Z3.Arithmetic.Integer.numeral_to_string e))))
  else if Z3.Expr.is_const e then
    let name = func_name e in
    Option.map (fun v -> mk_expr (EVar v)) (Hashtbl.find_opt env.z3_vars name)
  else if Z3.Boolean.is_not e then begin
    match Z3.Expr.get_args e with
    | [ a ] -> Option.map (fun a -> mk_expr (EUn (Not, a))) (fo_of_z3_expr env a)
    | _ -> None
  end
  else if Z3.Arithmetic.is_uminus e then begin
    match Z3.Expr.get_args e with
    | [ a ] -> Option.map (fun a -> mk_expr (EUn (Neg, a))) (fo_of_z3_expr env a)
    | _ -> None
  end
  else if Z3.Boolean.is_and e then
    let rec fold = function
      | [] -> Some (mk_expr (ELitBool true))
      | [ x ] -> fo_of_z3_expr env x
      | x :: rest ->
          let* x = fo_of_z3_expr env x in
          let* rest = fold rest in
          Some (mk_expr (EBin (And, x, rest)))
    in
    fold (Z3.Expr.get_args e)
  else if Z3.Boolean.is_or e then
    let rec fold = function
      | [] -> Some (mk_expr (ELitBool false))
      | [ x ] -> fo_of_z3_expr env x
      | x :: rest ->
          let* x = fo_of_z3_expr env x in
          let* rest = fold rest in
          Some (mk_expr (EBin (Or, x, rest)))
    in
    fold (Z3.Expr.get_args e)
  else if Z3.Arithmetic.is_add e || Z3.Arithmetic.is_sub e || Z3.Arithmetic.is_mul e then
    let op =
      if Z3.Arithmetic.is_add e then Add else if Z3.Arithmetic.is_sub e then Sub else Mul
    in
    let rec fold = function
      | [] -> None
      | [ x ] -> fo_of_z3_expr env x
      | x :: rest ->
          let* x = fo_of_z3_expr env x in
          let* rest = fold rest in
          Some (mk_expr (EBin (op, x, rest)))
    in
    fold (Z3.Expr.get_args e)
  else if Z3.Arithmetic.is_div e || Z3.Arithmetic.is_idiv e then begin
    match Z3.Expr.get_args e with
    | [ a; b ] ->
        let* a = fo_of_z3_expr env a in
        let* b = fo_of_z3_expr env b in
        Some (mk_expr (EBin (Div, a, b)))
    | _ -> None
  end
  else None

let fo_of_z3_hexpr (env : z3_env) (e : Z3.Expr.expr) : hexpr option =
  if not (Z3.Expr.is_const e) then
    let name = func_name e in
    match (Hashtbl.find_opt env.z3_preks name, Z3.Expr.get_args e) with
    | Some k, [ arg ] -> begin
        match fo_of_z3_expr env arg with
        | Some ({ expr = EVar v; _ }) -> Some { hexpr = HPreK (v, k); loc = None }
        | _ -> None
      end
    | _ -> Option.map Core_syntax_builders.hexpr_of_expr (fo_of_z3_expr env e)
  else Option.map Core_syntax_builders.hexpr_of_expr (fo_of_z3_expr env e)

let rec fo_of_z3_formula (env : z3_env) (e : Z3.Expr.expr) : Core_syntax.hexpr option =
  if Z3.Boolean.is_true e then Some (Core_syntax_builders.mk_hbool true)
  else if Z3.Boolean.is_false e then Some (Core_syntax_builders.mk_hbool false)
  else if Z3.Boolean.is_not e then begin
    match Z3.Expr.get_args e with
    | [ a ] ->
        let open Option in
        let* a = fo_of_z3_formula env a in
        Some (Core_syntax_builders.mk_hnot a)
    | _ -> None
  end
  else if Z3.Boolean.is_and e then
    List.fold_right
      (fun x acc ->
        let open Option in
        let* x = fo_of_z3_formula env x in
        let* acc = acc in
        Some (x :: acc))
      (Z3.Expr.get_args e) (Some [])
    |> Option.map rebuild_and
  else if Z3.Boolean.is_or e then
    List.fold_right
      (fun x acc ->
        let open Option in
        let* x = fo_of_z3_formula env x in
        let* acc = acc in
        Some (x :: acc))
      (Z3.Expr.get_args e) (Some [])
    |> Option.map rebuild_or
  else if Z3.Boolean.is_implies e then begin
    match Z3.Expr.get_args e with
    | [ a; b ] ->
        let open Option in
        let* a = fo_of_z3_formula env a in
        let* b = fo_of_z3_formula env b in
        Some (Core_syntax_builders.mk_himp a b)
    | _ -> None
  end
  else if Z3.Boolean.is_eq e then begin
    match Z3.Expr.get_args e with
    | [ a; b ] ->
        let open Option in
        let* a = fo_of_z3_hexpr env a in
        let* b = fo_of_z3_hexpr env b in
        let a, r, b = normalize_rel a REq b in
        Some (Core_syntax_builders.mk_hexpr (HCmp (r, a, b)))
    | _ -> None
  end
  else if Z3.Arithmetic.is_le e || Z3.Arithmetic.is_ge e || Z3.Arithmetic.is_lt e || Z3.Arithmetic.is_gt e then
    begin
      match Z3.Expr.get_args e with
      | [ a; b ] ->
          let rel =
            if Z3.Arithmetic.is_le e then RLe
            else if Z3.Arithmetic.is_ge e then RGe
            else if Z3.Arithmetic.is_lt e then RLt
            else RGt
          in
          let open Option in
          let* a = fo_of_z3_hexpr env a in
          let* b = fo_of_z3_hexpr env b in
          let a, rel, b = normalize_rel a rel b in
          Some (Core_syntax_builders.mk_hexpr (HCmp (rel, a, b)))
      | _ -> None
    end
  else
    let name = func_name e in
    match Hashtbl.find_opt env.z3_preds name with
    | Some id ->
        let rec map acc = function
          | [] -> Some (List.rev acc)
          | x :: xs -> begin
              match fo_of_z3_hexpr env x with
              | Some x -> map (x :: acc) xs
              | None -> None
            end
        in
        Option.map (fun hs -> Core_syntax_builders.mk_hpred id hs) (map [] (Z3.Expr.get_args e))
    | None ->
        Option.map
          (fun h -> Core_syntax_builders.mk_hexpr (HCmp (REq, h, Core_syntax_builders.mk_hbool true)))
          (fo_of_z3_hexpr env e)

let simplify_fo_formula (f : Core_syntax.hexpr) : Core_syntax.hexpr option =
  if fo_simplifier_forced_off () then None
  else
    let t0 = Unix.gettimeofday () in
    let finish out =
      External_timing.record_z3 ~elapsed_s:(Unix.gettimeofday () -. t0);
      out
    in
    try
      let env = make_z3_env f in
      let e0 = z3_of_fo env f in
      let e1 = Z3.Expr.simplify e0 None in
      let goal = Z3.Goal.mk_goal env.ctx true false false in
      Z3.Goal.add goal [ e1 ];
      let tactic =
        Z3.Tactic.and_then env.ctx
          (Z3.Tactic.mk_tactic env.ctx "ctx-simplify")
          (Z3.Tactic.mk_tactic env.ctx "propagate-values")
          [ Z3.Tactic.mk_tactic env.ctx "unit-subsume-simplify" ]
      in
      let result = Z3.Tactic.apply tactic goal None in
      let e2 =
        match Z3.Tactic.ApplyResult.get_subgoals result with
        | [] -> Z3.Boolean.mk_true env.ctx
        | [ subgoal ] -> Z3.Goal.as_expr subgoal
        | subgoals ->
            Z3.Boolean.mk_and env.ctx (List.map Z3.Goal.as_expr subgoals)
      in
      finish (fo_of_z3_formula env e2)
    with _ -> finish None
