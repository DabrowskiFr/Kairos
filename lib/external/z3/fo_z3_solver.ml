open Ast
open Ast_pretty
open Fo_formula

let mk_iexpr iexpr = { iexpr; loc = None }
let ( let* ) = Option.bind

type smt_sort = SInt | SBool

type smt_env = {
  vars : (ident, smt_sort) Hashtbl.t;
  preds : (string, unit) Hashtbl.t;
  preks : (string, unit) Hashtbl.t;
}

type z3_env = {
  ctx : Z3.context;
  vars : (ident, smt_sort) Hashtbl.t;
  z3_vars : (string, ident) Hashtbl.t;
  z3_preds : (string, ident) Hashtbl.t;
  z3_preks : (string, int) Hashtbl.t;
}

let z3_status_cache : (string, bool option) Hashtbl.t = Hashtbl.create 257
let z3_implies_cache : (string, bool option) Hashtbl.t = Hashtbl.create 257

let starts_with ~(prefix : string) (s : string) : bool =
  let n = String.length prefix in
  String.length s >= n && String.sub s 0 n = prefix

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

let rec infer_iexpr_sort (vars : (ident, smt_sort) Hashtbl.t) (e : iexpr) : smt_sort option =
  let unify_var v s =
    match Hashtbl.find_opt vars v with
    | None ->
        Hashtbl.add vars v s;
        Some s
    | Some s' -> Some s'
  in
  match e.iexpr with
  | ILitInt _ -> Some SInt
  | ILitBool _ -> Some SBool
  | IVar v -> Hashtbl.find_opt vars v
  | IUn (Neg, a) ->
      let _ = infer_iexpr_sort vars a in
      Some SInt
  | IUn (Not, a) ->
      let _ = infer_iexpr_sort vars a in
      Some SBool
  | IBin (Add, a, b) | IBin (Sub, a, b) | IBin (Mul, a, b) | IBin (Div, a, b) ->
      let _ = infer_iexpr_sort vars a in
      let _ = infer_iexpr_sort vars b in
      Some SInt
  | IBin (And, a, b) | IBin (Or, a, b) ->
      let _ = infer_iexpr_sort vars a in
      let _ = infer_iexpr_sort vars b in
      Some SBool
  | IBin (Lt, a, b) | IBin (Le, a, b) | IBin (Gt, a, b) | IBin (Ge, a, b) ->
      let _ = infer_iexpr_sort vars a in
      let _ = infer_iexpr_sort vars b in
      Some SBool
  | IBin (Eq, a, b) | IBin (Neq, a, b) -> begin
      let sa = infer_iexpr_sort vars a in
      let sb = infer_iexpr_sort vars b in
      let operand_sort =
        match (sa, sb) with Some s, _ | _, Some s -> s | None, None -> SInt
      in
      (match a.iexpr with IVar v -> ignore (unify_var v operand_sort) | _ -> ());
      (match b.iexpr with IVar v -> ignore (unify_var v operand_sort) | _ -> ());
      Some SBool
    end
  | IPar a -> infer_iexpr_sort vars a

let infer_hexpr_sort vars = function
  | HNow e | HPreK (e, _) -> infer_iexpr_sort vars e

let infer_atom_sorts (f : fo_atom) (vars : (ident, smt_sort) Hashtbl.t) : unit =
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
          begin
            match h1 with HNow { iexpr = IVar v; _ } | HPreK ({ iexpr = IVar v; _ }, _) ->
              Hashtbl.replace vars v s
            | _ -> ()
          end;
          begin
            match h2 with HNow { iexpr = IVar v; _ } | HPreK ({ iexpr = IVar v; _ }, _) ->
              Hashtbl.replace vars v s
            | _ -> ()
          end
    end
  | FPred (_, hs) -> List.iter (fun h -> ignore (infer_hexpr_sort vars h)) hs

let infer_formula_sorts_fo (f : Fo_formula.t) : (ident, smt_sort) Hashtbl.t =
  let vars = Hashtbl.create 32 in
  let rec go = function
    | Fo_formula.FTrue | Fo_formula.FFalse -> ()
    | Fo_formula.FAtom a -> infer_atom_sorts a vars
    | Fo_formula.FNot a -> go a
    | Fo_formula.FAnd (a, b) | Fo_formula.FOr (a, b) | Fo_formula.FImp (a, b) ->
        go a;
        go b
  in
  go f;
  vars

let infer_formula_sorts_ltl (f : ltl) : (ident, smt_sort) Hashtbl.t =
  let vars = Hashtbl.create 32 in
  let rec go = function
    | LTrue | LFalse -> ()
    | LAtom a -> infer_atom_sorts a vars
    | LNot a | LX a | LG a -> go a
    | LAnd (a, b) | LOr (a, b) | LImp (a, b) | LW (a, b) ->
        go a;
        go b
  in
  go f;
  vars

let make_env (f : ltl) : smt_env =
  { vars = infer_formula_sorts_ltl f; preds = Hashtbl.create 16; preks = Hashtbl.create 16 }

let make_z3_env (f : Fo_formula.t) : z3_env =
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

let rec z3_of_iexpr (env : z3_env) (e : iexpr) : Z3.Expr.expr * smt_sort =
  match e.iexpr with
  | ILitInt i -> (Z3.Arithmetic.Integer.mk_numeral_i env.ctx i, SInt)
  | ILitBool b -> (Z3.Boolean.mk_val env.ctx b, SBool)
  | IVar v ->
      let sort = Hashtbl.find_opt env.vars v |> Option.value ~default:SInt in
      let name = smt_var_name v in
      Hashtbl.replace env.z3_vars name v;
      (Z3.Expr.mk_const_s env.ctx name (z3_sort env sort), sort)
  | IUn (Neg, a) ->
      let a, _ = z3_of_iexpr env a in
      (Z3.Arithmetic.mk_unary_minus env.ctx a, SInt)
  | IUn (Not, a) ->
      let a, _ = z3_of_iexpr env a in
      (Z3.Boolean.mk_not env.ctx a, SBool)
  | IBin (Add, a, b) ->
      let a, _ = z3_of_iexpr env a in
      let b, _ = z3_of_iexpr env b in
      (Z3.Arithmetic.mk_add env.ctx [ a; b ], SInt)
  | IBin (Sub, a, b) ->
      let a, _ = z3_of_iexpr env a in
      let b, _ = z3_of_iexpr env b in
      (Z3.Arithmetic.mk_sub env.ctx [ a; b ], SInt)
  | IBin (Mul, a, b) ->
      let a, _ = z3_of_iexpr env a in
      let b, _ = z3_of_iexpr env b in
      (Z3.Arithmetic.mk_mul env.ctx [ a; b ], SInt)
  | IBin (Div, a, b) ->
      let a, _ = z3_of_iexpr env a in
      let b, _ = z3_of_iexpr env b in
      (Z3.Arithmetic.mk_div env.ctx a b, SInt)
  | IBin (And, a, b) ->
      let a, _ = z3_of_iexpr env a in
      let b, _ = z3_of_iexpr env b in
      (Z3.Boolean.mk_and env.ctx [ a; b ], SBool)
  | IBin (Or, a, b) ->
      let a, _ = z3_of_iexpr env a in
      let b, _ = z3_of_iexpr env b in
      (Z3.Boolean.mk_or env.ctx [ a; b ], SBool)
  | IBin (Eq, a, b) ->
      let a, _ = z3_of_iexpr env a in
      let b, _ = z3_of_iexpr env b in
      (Z3.Boolean.mk_eq env.ctx a b, SBool)
  | IBin (Neq, a, b) ->
      let a, _ = z3_of_iexpr env a in
      let b, _ = z3_of_iexpr env b in
      (Z3.Boolean.mk_not env.ctx (Z3.Boolean.mk_eq env.ctx a b), SBool)
  | IBin (Lt, a, b) ->
      let a, _ = z3_of_iexpr env a in
      let b, _ = z3_of_iexpr env b in
      (Z3.Arithmetic.mk_lt env.ctx a b, SBool)
  | IBin (Le, a, b) ->
      let a, _ = z3_of_iexpr env a in
      let b, _ = z3_of_iexpr env b in
      (Z3.Arithmetic.mk_le env.ctx a b, SBool)
  | IBin (Gt, a, b) ->
      let a, _ = z3_of_iexpr env a in
      let b, _ = z3_of_iexpr env b in
      (Z3.Arithmetic.mk_gt env.ctx a b, SBool)
  | IBin (Ge, a, b) ->
      let a, _ = z3_of_iexpr env a in
      let b, _ = z3_of_iexpr env b in
      (Z3.Arithmetic.mk_ge env.ctx a b, SBool)
  | IPar e -> z3_of_iexpr env e

let z3_of_hexpr (env : z3_env) = function
  | HNow e -> z3_of_iexpr env e
  | HPreK (e, k) ->
      let arg, sort = z3_of_iexpr env e in
      let name = smt_prek_name k sort in
      let fd = Z3.FuncDecl.mk_func_decl_s env.ctx name [ z3_sort env sort ] (z3_sort env sort) in
      Hashtbl.replace env.z3_preks name k;
      (Z3.Expr.mk_app env.ctx fd [ arg ], sort)

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

let rec z3_of_fo (env : z3_env) = function
  | FTrue -> Z3.Boolean.mk_true env.ctx
  | FFalse -> Z3.Boolean.mk_false env.ctx
  | FAtom a -> z3_of_fo_atom env a
  | FNot a -> Z3.Boolean.mk_not env.ctx (z3_of_fo env a)
  | FAnd (a, b) -> Z3.Boolean.mk_and env.ctx [ z3_of_fo env a; z3_of_fo env b ]
  | FOr (a, b) -> Z3.Boolean.mk_or env.ctx [ z3_of_fo env a; z3_of_fo env b ]
  | FImp (a, b) -> Z3.Boolean.mk_implies env.ctx (z3_of_fo env a) (z3_of_fo env b)

let func_name (e : Z3.Expr.expr) : string =
  Z3.Expr.get_func_decl e |> Z3.FuncDecl.get_name |> Z3.Symbol.get_string

let rebuild_and = function
  | [] -> FTrue
  | [ x ] -> x
  | x :: xs -> List.fold_left (fun acc y -> FAnd (acc, y)) x xs

let rebuild_or = function
  | [] -> FFalse
  | [ x ] -> x
  | x :: xs -> List.fold_left (fun acc y -> FOr (acc, y)) x xs

let is_literal_iexpr (e : iexpr) =
  match e.iexpr with ILitInt _ | ILitBool _ -> true | _ -> false

let is_const_hexpr = function HNow e -> is_literal_iexpr e | HPreK _ -> false

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

let rec fo_of_z3_iexpr (env : z3_env) (e : Z3.Expr.expr) : iexpr option =
  if Z3.Boolean.is_true e then Some (mk_iexpr (ILitBool true))
  else if Z3.Boolean.is_false e then Some (mk_iexpr (ILitBool false))
  else if Z3.Arithmetic.is_int_numeral e then
    Some (mk_iexpr (ILitInt (int_of_string (Z3.Arithmetic.Integer.numeral_to_string e))))
  else if Z3.Expr.is_const e then
    let name = func_name e in
    Option.map (fun v -> mk_iexpr (IVar v)) (Hashtbl.find_opt env.z3_vars name)
  else if Z3.Boolean.is_not e then begin
    match Z3.Expr.get_args e with
    | [ a ] -> Option.map (fun a -> mk_iexpr (IUn (Not, a))) (fo_of_z3_iexpr env a)
    | _ -> None
  end
  else if Z3.Arithmetic.is_uminus e then begin
    match Z3.Expr.get_args e with
    | [ a ] -> Option.map (fun a -> mk_iexpr (IUn (Neg, a))) (fo_of_z3_iexpr env a)
    | _ -> None
  end
  else if Z3.Boolean.is_and e then
    let rec fold = function
      | [] -> Some (mk_iexpr (ILitBool true))
      | [ x ] -> fo_of_z3_iexpr env x
      | x :: rest ->
          let* x = fo_of_z3_iexpr env x in
          let* rest = fold rest in
          Some (mk_iexpr (IBin (And, x, rest)))
    in
    fold (Z3.Expr.get_args e)
  else if Z3.Boolean.is_or e then
    let rec fold = function
      | [] -> Some (mk_iexpr (ILitBool false))
      | [ x ] -> fo_of_z3_iexpr env x
      | x :: rest ->
          let* x = fo_of_z3_iexpr env x in
          let* rest = fold rest in
          Some (mk_iexpr (IBin (Or, x, rest)))
    in
    fold (Z3.Expr.get_args e)
  else if Z3.Arithmetic.is_add e || Z3.Arithmetic.is_sub e || Z3.Arithmetic.is_mul e then
    let op =
      if Z3.Arithmetic.is_add e then Add else if Z3.Arithmetic.is_sub e then Sub else Mul
    in
    let rec fold = function
      | [] -> None
      | [ x ] -> fo_of_z3_iexpr env x
      | x :: rest ->
          let* x = fo_of_z3_iexpr env x in
          let* rest = fold rest in
          Some (mk_iexpr (IBin (op, x, rest)))
    in
    fold (Z3.Expr.get_args e)
  else if Z3.Arithmetic.is_div e || Z3.Arithmetic.is_idiv e then begin
    match Z3.Expr.get_args e with
    | [ a; b ] ->
        let* a = fo_of_z3_iexpr env a in
        let* b = fo_of_z3_iexpr env b in
        Some (mk_iexpr (IBin (Div, a, b)))
    | _ -> None
  end
  else None

let fo_of_z3_hexpr (env : z3_env) (e : Z3.Expr.expr) : hexpr option =
  if not (Z3.Expr.is_const e) then
    let name = func_name e in
    match (Hashtbl.find_opt env.z3_preks name, Z3.Expr.get_args e) with
    | Some k, [ arg ] -> begin
        match fo_of_z3_iexpr env arg with
        | Some ({ iexpr = IVar _; _ } as arg) -> Some (HPreK (arg, k))
        | _ -> None
      end
    | _ -> Option.map (fun e -> HNow e) (fo_of_z3_iexpr env e)
  else Option.map (fun e -> HNow e) (fo_of_z3_iexpr env e)

let rec fo_of_z3_formula (env : z3_env) (e : Z3.Expr.expr) : Fo_formula.t option =
  if Z3.Boolean.is_true e then Some FTrue
  else if Z3.Boolean.is_false e then Some FFalse
  else if Z3.Boolean.is_not e then begin
    match Z3.Expr.get_args e with
    | [ a ] ->
        let open Option in
        let* a = fo_of_z3_formula env a in
        Some (FNot a)
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
        Some (FImp (a, b))
    | _ -> None
  end
  else if Z3.Boolean.is_eq e then begin
    match Z3.Expr.get_args e with
    | [ a; b ] ->
        let open Option in
        let* a = fo_of_z3_hexpr env a in
        let* b = fo_of_z3_hexpr env b in
        let a, r, b = normalize_rel a REq b in
        Some (FAtom (FRel (a, r, b)))
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
          Some (FAtom (FRel (a, rel, b)))
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
        Option.map (fun hs -> FAtom (FPred (id, hs))) (map [] (Z3.Expr.get_args e))
    | None ->
        Option.map
          (fun h -> FAtom (FRel (h, REq, HNow (mk_iexpr (ILitBool true)))))
          (fo_of_z3_hexpr env e)

let simplify_fo_formula (f : Fo_formula.t) : Fo_formula.t option =
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

let rec smt_of_iexpr (env : smt_env) (e : iexpr) : string * smt_sort =
  match e.iexpr with
  | ILitInt i -> (string_of_int i, SInt)
  | ILitBool true -> ("true", SBool)
  | ILitBool false -> ("false", SBool)
  | IVar v ->
      let sort = Hashtbl.find_opt env.vars v |> Option.value ~default:SInt in
      Hashtbl.replace env.vars v sort;
      (smt_var_name v, sort)
  | IUn (Neg, a) ->
      let sa, _ = smt_of_iexpr env a in
      ("(- " ^ sa ^ ")", SInt)
  | IUn (Not, a) ->
      let sa, _ = smt_of_iexpr env a in
      ("(not " ^ sa ^ ")", SBool)
  | IBin (Add, a, b) ->
      let sa, _ = smt_of_iexpr env a in
      let sb, _ = smt_of_iexpr env b in
      ("(+ " ^ sa ^ " " ^ sb ^ ")", SInt)
  | IBin (Sub, a, b) ->
      let sa, _ = smt_of_iexpr env a in
      let sb, _ = smt_of_iexpr env b in
      ("(- " ^ sa ^ " " ^ sb ^ ")", SInt)
  | IBin (Mul, a, b) ->
      let sa, _ = smt_of_iexpr env a in
      let sb, _ = smt_of_iexpr env b in
      ("(* " ^ sa ^ " " ^ sb ^ ")", SInt)
  | IBin (Div, a, b) ->
      let sa, _ = smt_of_iexpr env a in
      let sb, _ = smt_of_iexpr env b in
      ("(div " ^ sa ^ " " ^ sb ^ ")", SInt)
  | IBin (And, a, b) ->
      let sa, _ = smt_of_iexpr env a in
      let sb, _ = smt_of_iexpr env b in
      ("(and " ^ sa ^ " " ^ sb ^ ")", SBool)
  | IBin (Or, a, b) ->
      let sa, _ = smt_of_iexpr env a in
      let sb, _ = smt_of_iexpr env b in
      ("(or " ^ sa ^ " " ^ sb ^ ")", SBool)
  | IBin (Eq, a, b) ->
      let sa, _ = smt_of_iexpr env a in
      let sb, _ = smt_of_iexpr env b in
      ("(= " ^ sa ^ " " ^ sb ^ ")", SBool)
  | IBin (Neq, a, b) ->
      let sa, _ = smt_of_iexpr env a in
      let sb, _ = smt_of_iexpr env b in
      ("(not (= " ^ sa ^ " " ^ sb ^ "))", SBool)
  | IBin (Lt, a, b) ->
      let sa, _ = smt_of_iexpr env a in
      let sb, _ = smt_of_iexpr env b in
      ("(< " ^ sa ^ " " ^ sb ^ ")", SBool)
  | IBin (Le, a, b) ->
      let sa, _ = smt_of_iexpr env a in
      let sb, _ = smt_of_iexpr env b in
      ("(<= " ^ sa ^ " " ^ sb ^ ")", SBool)
  | IBin (Gt, a, b) ->
      let sa, _ = smt_of_iexpr env a in
      let sb, _ = smt_of_iexpr env b in
      ("(> " ^ sa ^ " " ^ sb ^ ")", SBool)
  | IBin (Ge, a, b) ->
      let sa, _ = smt_of_iexpr env a in
      let sb, _ = smt_of_iexpr env b in
      ("(>= " ^ sa ^ " " ^ sb ^ ")", SBool)
  | IPar a -> smt_of_iexpr env a

let smt_of_hexpr (env : smt_env) = function
  | HNow e -> smt_of_iexpr env e
  | HPreK (e, k) ->
      let se, sort = smt_of_iexpr env e in
      let fname = smt_prek_name k sort in
      Hashtbl.replace env.preks fname ();
      ("(" ^ fname ^ " " ^ se ^ ")", sort)

let smt_of_fo_atom (env : smt_env) = function
  | FRel (h1, REq, h2) ->
      let s1, _ = smt_of_hexpr env h1 in
      let s2, _ = smt_of_hexpr env h2 in
      "(= " ^ s1 ^ " " ^ s2 ^ ")"
  | FRel (h1, RNeq, h2) ->
      let s1, _ = smt_of_hexpr env h1 in
      let s2, _ = smt_of_hexpr env h2 in
      "(not (= " ^ s1 ^ " " ^ s2 ^ "))"
  | FRel (h1, RLt, h2) ->
      let s1, _ = smt_of_hexpr env h1 in
      let s2, _ = smt_of_hexpr env h2 in
      "(< " ^ s1 ^ " " ^ s2 ^ ")"
  | FRel (h1, RLe, h2) ->
      let s1, _ = smt_of_hexpr env h1 in
      let s2, _ = smt_of_hexpr env h2 in
      "(<= " ^ s1 ^ " " ^ s2 ^ ")"
  | FRel (h1, RGt, h2) ->
      let s1, _ = smt_of_hexpr env h1 in
      let s2, _ = smt_of_hexpr env h2 in
      "(> " ^ s1 ^ " " ^ s2 ^ ")"
  | FRel (h1, RGe, h2) ->
      let s1, _ = smt_of_hexpr env h1 in
      let s2, _ = smt_of_hexpr env h2 in
      "(>= " ^ s1 ^ " " ^ s2 ^ ")"
  | FPred (id, hs) ->
      let args = List.map (smt_of_hexpr env) hs in
      let name = smt_pred_name id (List.length hs) in
      Hashtbl.replace env.preds name ();
      "(" ^ name ^ (if args = [] then "" else " " ^ String.concat " " (List.map fst args)) ^ ")"

let rec smt_of_ltl (env : smt_env) = function
  | LTrue -> "true"
  | LFalse -> "false"
  | LAtom a -> smt_of_fo_atom env a
  | LNot a -> "(not " ^ smt_of_ltl env a ^ ")"
  | LAnd (a, b) -> "(and " ^ smt_of_ltl env a ^ " " ^ smt_of_ltl env b ^ ")"
  | LOr (a, b) -> "(or " ^ smt_of_ltl env a ^ " " ^ smt_of_ltl env b ^ ")"
  | LImp (a, b) -> "(=> " ^ smt_of_ltl env a ^ " " ^ smt_of_ltl env b ^ ")"
  | LX _ | LG _ | LW _ -> "true"

let declarations_of_env (env : smt_env) : string list =
  let decls = ref [] in
  Hashtbl.iter
    (fun v sort ->
      decls := Printf.sprintf "(declare-fun %s () %s)" (smt_var_name v) (string_of_sort sort) :: !decls)
    env.vars;
  Hashtbl.iter
    (fun name () ->
      let arity =
        try
          let i = String.rindex name '_' in
          int_of_string (String.sub name (i + 1) (String.length name - i - 1))
        with _ -> 0
      in
      let args = List.init arity (fun _ -> "Int") |> String.concat " " in
      let args = if args = "" then "" else args ^ " " in
      decls := Printf.sprintf "(declare-fun %s (%s) Bool)" name args :: !decls)
    env.preds;
  Hashtbl.iter
    (fun name () ->
      let sort =
        if String.ends_with ~suffix:"_bool" name then "Bool"
        else "Int"
      in
      decls := Printf.sprintf "(declare-fun %s (%s) %s)" name sort sort :: !decls)
    env.preks;
  List.rev !decls

let read_all (ic : in_channel) : string =
  let buf = Buffer.create 1024 in
  (try
     while true do
       Buffer.add_channel buf ic 1024
     done
   with End_of_file -> ());
  Buffer.contents buf

let z3_command () : string =
  let env_path =
    match Sys.getenv_opt "KAIROS_Z3" with Some p when Sys.file_exists p -> Some p | _ -> None
  in
  match env_path with
  | Some p -> Filename.quote p ^ " -in -smt2"
  | None ->
      let candidates =
        [
          "/opt/homebrew/bin/z3";
          "/usr/local/bin/z3";
          "/usr/bin/z3";
          (match Sys.getenv_opt "OPAM_SWITCH_PREFIX" with
          | Some p -> Filename.concat p "bin/z3"
          | None -> "");
        ]
        |> List.filter (fun p -> p <> "" && Sys.file_exists p)
      in
      (match candidates with
      | p :: _ -> Filename.quote p ^ " -in -smt2"
      | [] ->
          let opam =
            [ "/opt/homebrew/bin/opam"; "/usr/local/bin/opam"; "/usr/bin/opam" ]
            |> List.find_opt Sys.file_exists
          in
          match opam with
          | Some p -> Filename.quote p ^ " exec -- z3 -in -smt2"
          | None -> "")

let solver_enabled () = (not (fo_simplifier_forced_off ())) && z3_command () <> ""

let run_z3_query (query_key : string) (script : string) : bool option =
  if not (solver_enabled ()) then None
  else
    match Hashtbl.find_opt z3_status_cache query_key with
    | Some cached -> cached
    | None ->
        let cmd = z3_command () in
        if cmd = "" then None
        else
          let ic, oc, ec = Unix.open_process_full cmd (Unix.environment ()) in
          output_string oc script;
          close_out oc;
          let stdout = read_all ic |> String.trim in
          let _stderr = read_all ec in
          let _ = Unix.close_process_full (ic, oc, ec) in
          let result =
            if starts_with ~prefix:"unsat" stdout then Some true
            else if starts_with ~prefix:"sat" stdout then Some false
            else None
          in
          Hashtbl.replace z3_status_cache query_key result;
          result

let prove_formula (f : ltl) : bool option =
  let env = make_env f in
  let body = smt_of_ltl env f in
  let script =
    String.concat "\n"
      (["(set-logic ALL)"] @ declarations_of_env env @ [ "(assert (not " ^ body ^ "))"; "(check-sat)" ])
    ^ "\n"
  in
  run_z3_query ("valid:" ^ string_of_ltl f) script

let unsat_formula (f : ltl) : bool option =
  let env = make_env f in
  let body = smt_of_ltl env f in
  let script =
    String.concat "\n" (["(set-logic ALL)"] @ declarations_of_env env @ [ "(assert " ^ body ^ ")"; "(check-sat)" ])
    ^ "\n"
  in
  run_z3_query ("unsat:" ^ string_of_ltl f) script

let implies_formula (a : ltl) (b : ltl) : bool option =
  let key = string_of_ltl a ^ " => " ^ string_of_ltl b in
  match Hashtbl.find_opt z3_implies_cache key with
  | Some cached -> cached
  | None ->
      let result = prove_formula (LImp (a, b)) in
      Hashtbl.replace z3_implies_cache key result;
      result
