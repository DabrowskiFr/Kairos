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
open Pretty

let mk_expr expr = { expr; loc = None }
let ( let* ) = Option.bind

type smt_sort = SInt | SBool

exception Unsupported_enum_formula

type z3_env = {
  ctx : Z3.context;
  vars : (ident, smt_sort) Hashtbl.t;
  z3_vars : (string, ident) Hashtbl.t;
  z3_preds : (string, ident) Hashtbl.t;
  z3_preks : (string, int) Hashtbl.t;
}

let mk_h desc = Core_syntax_builders.mk_hexpr desc
let htrue = Core_syntax_builders.mk_hbool true
let hfalse = Core_syntax_builders.mk_hbool false

let is_htrue = function { hexpr = HLitBool true; _ } -> true | _ -> false
let is_hfalse = function { hexpr = HLitBool false; _ } -> true | _ -> false

let rec key_of_hexpr (h : hexpr) : string =
  match h.hexpr with
  | HLitInt n -> "i:" ^ string_of_int n
  | HLitBool b -> "b:" ^ string_of_bool b
  | HLitEnum c -> "e:" ^ c
  | HVar v -> "v:" ^ v
  | HPreK (v, k) -> "p:" ^ string_of_int k ^ ":" ^ v
  | HPred (id, hs) -> "pred:" ^ id ^ "(" ^ String.concat "," (List.map key_of_hexpr hs) ^ ")"
  | HUn (op, inner) ->
      let op_s = match op with Neg -> "neg" | Not -> "not" in
      op_s ^ "(" ^ key_of_hexpr inner ^ ")"
  | HBin (op, a, b) ->
      let op_s =
        match op with
        | Add -> "+"
        | Sub -> "-"
        | Mul -> "*"
        | Div -> "/"
        | And -> "and"
        | Or -> "or"
      in
      op_s ^ "(" ^ key_of_hexpr a ^ "," ^ key_of_hexpr b ^ ")"
  | HCmp (op, a, b) ->
      let op_s =
        match op with
        | REq -> "="
        | RNeq -> "<>"
        | RLt -> "<"
        | RLe -> "<="
        | RGt -> ">"
        | RGe -> ">="
      in
      op_s ^ "(" ^ key_of_hexpr a ^ "," ^ key_of_hexpr b ^ ")"

let const_key_of_hexpr = function
  | { hexpr = HLitInt n; _ } -> Some ("i:" ^ string_of_int n)
  | { hexpr = HLitBool b; _ } -> Some ("b:" ^ string_of_bool b)
  | { hexpr = HLitEnum c; _ } -> Some ("e:" ^ c)
  | _ -> None

let subject_key_of_hexpr = function
  | { hexpr = HVar v; _ } -> Some ("v:" ^ v)
  | { hexpr = HPreK (v, k); _ } -> Some ("p:" ^ string_of_int k ^ ":" ^ v)
  | _ -> None

type rel_lit = { subject : string; op : relop; value : string }

let rel_lit_of_hexpr (h : hexpr) : rel_lit option =
  match h.hexpr with
  | HCmp ((REq | RNeq as op), a, b) -> begin
      match (subject_key_of_hexpr a, const_key_of_hexpr b) with
      | Some subject, Some value -> Some { subject; op; value }
      | _ -> begin
          match (subject_key_of_hexpr b, const_key_of_hexpr a) with
          | Some subject, Some value -> Some { subject; op; value }
          | _ -> None
        end
    end
  | _ -> None

let rec literal_key (h : hexpr) : (string * bool) option =
  match rel_lit_of_hexpr h with
  | Some { subject; op = REq; value } -> Some ("rel:" ^ subject ^ ":" ^ value, true)
  | Some { subject; op = RNeq; value } -> Some ("rel:" ^ subject ^ ":" ^ value, false)
  | Some _ -> None
  | None -> begin
      match h.hexpr with
      | HUn (Not, inner) -> Option.map (fun (key, sign) -> (key, not sign)) (literal_key inner)
      | HVar _ | HPred _ -> Some ("bool:" ^ key_of_hexpr h, true)
      | _ -> None
    end

let are_complements a b =
  match (literal_key a, literal_key b) with
  | Some (ka, sa), Some (kb, sb) -> String.equal ka kb && Bool.equal sa (not sb)
  | _ -> false

let negate_relop = function
  | REq -> RNeq
  | RNeq -> REq
  | RLt -> RGe
  | RLe -> RGt
  | RGt -> RLe
  | RGe -> RLt

let eval_const_rel (op : relop) (a : hexpr) (b : hexpr) : bool option =
  match (a.hexpr, b.hexpr) with
  | HLitInt x, HLitInt y ->
      Some
        (match op with
        | REq -> x = y
        | RNeq -> x <> y
        | RLt -> x < y
        | RLe -> x <= y
        | RGt -> x > y
        | RGe -> x >= y)
  | HLitBool x, HLitBool y ->
      Some
        (match op with
        | REq -> x = y
        | RNeq -> x <> y
        | RLt | RLe | RGt | RGe -> false)
  | HLitEnum x, HLitEnum y ->
      Some
        (match op with
        | REq -> String.equal x y
        | RNeq -> not (String.equal x y)
        | RLt | RLe | RGt | RGe -> false)
  | _ -> None

let rec flatten_bool (op : binop) (h : hexpr) : hexpr list =
  match h.hexpr with
  | HBin (op', a, b) when op = op' -> flatten_bool op a @ flatten_bool op b
  | _ -> [ h ]

let dedup_hexprs (xs : hexpr list) : hexpr list =
  let seen = Hashtbl.create (List.length xs * 2 + 1) in
  let rec loop acc = function
    | [] -> List.rev acc
    | x :: rest ->
        let key = key_of_hexpr x in
        if Hashtbl.mem seen key then loop acc rest
        else (
          Hashtbl.add seen key ();
          loop (x :: acc) rest)
  in
  loop [] xs

let and_has_contradiction (xs : hexpr list) : bool =
  let equalities = Hashtbl.create 16 in
  let disequalities = Hashtbl.create 16 in
  List.exists
    (fun h ->
      match rel_lit_of_hexpr h with
      | None -> false
      | Some { subject; op = REq; value } -> begin
          match Hashtbl.find_opt equalities subject with
          | Some prev when not (String.equal prev value) -> true
          | _ ->
              Hashtbl.replace equalities subject value;
              Hashtbl.mem disequalities (subject, value)
        end
      | Some { subject; op = RNeq; value } ->
          Hashtbl.replace disequalities (subject, value) ();
          begin
            match Hashtbl.find_opt equalities subject with
            | Some prev -> String.equal prev value
            | None -> false
          end
      | Some _ -> false)
    xs

let prune_redundant_disequalities (xs : hexpr list) : hexpr list =
  let equalities = Hashtbl.create 16 in
  List.iter
    (fun h ->
      match rel_lit_of_hexpr h with
      | Some { subject; op = REq; value } -> Hashtbl.replace equalities subject value
      | _ -> ())
    xs;
  List.filter
    (fun h ->
      match rel_lit_of_hexpr h with
      | Some { subject; op = RNeq; value } -> begin
          match Hashtbl.find_opt equalities subject with
          | Some known -> String.equal known value
          | None -> true
        end
      | _ -> true)
    xs

let or_has_tautology (xs : hexpr list) : bool =
  let seen_eq = Hashtbl.create 16 in
  let seen_neq = Hashtbl.create 16 in
  List.exists
    (fun h ->
      match rel_lit_of_hexpr h with
      | Some { subject; op = REq; value } ->
          let key = (subject, value) in
          if Hashtbl.mem seen_neq key then true
          else (
            Hashtbl.replace seen_eq key ();
            false)
      | Some { subject; op = RNeq; value } ->
          let key = (subject, value) in
          if Hashtbl.mem seen_eq key then true
          else (
            Hashtbl.replace seen_neq key ();
            false)
      | _ -> false)
    xs

let rebuild_and_syntax (xs : hexpr list) : hexpr =
  let xs = List.concat_map (flatten_bool And) xs in
  if List.exists is_hfalse xs || and_has_contradiction xs then hfalse
  else
    let xs =
      xs |> List.filter (fun h -> not (is_htrue h)) |> dedup_hexprs
      |> prune_redundant_disequalities |> dedup_hexprs
    in
    match xs with
    | [] -> htrue
    | [ x ] -> x
    | x :: rest -> List.fold_left Core_syntax_builders.mk_hand x rest

let simplify_disjunct_against_simple (simple : hexpr) (h : hexpr) : hexpr option =
  let conjuncts = flatten_bool And h in
  match conjuncts with
  | [ _ ] -> Some h
  | _ ->
      if List.exists (fun c -> key_of_hexpr c = key_of_hexpr simple) conjuncts then None
      else
        let pruned = List.filter (fun c -> not (are_complements simple c)) conjuncts in
        Some (rebuild_and_syntax pruned)

let resolve_or_pair (a : hexpr) (b : hexpr) : hexpr option =
  let ca = flatten_bool And a |> dedup_hexprs in
  let cb = flatten_bool And b |> dedup_hexprs in
  let keys_a = List.map (fun h -> (key_of_hexpr h, h)) ca in
  let keys_b = List.map (fun h -> (key_of_hexpr h, h)) cb in
  let common =
    keys_a
    |> List.filter_map (fun (key, h) ->
           if List.exists (fun (key_b, _) -> String.equal key key_b) keys_b then Some h
           else None)
  in
  let diff_a =
    ca
    |> List.filter (fun h ->
           not (List.exists (fun c -> String.equal (key_of_hexpr h) (key_of_hexpr c)) common))
  in
  let diff_b =
    cb
    |> List.filter (fun h ->
           not (List.exists (fun c -> String.equal (key_of_hexpr h) (key_of_hexpr c)) common))
  in
  match (diff_a, diff_b) with
  | [ da ], [ db ] when are_complements da db -> Some (rebuild_and_syntax common)
  | _ -> None

let rec resolve_or_once (xs : hexpr list) : hexpr list * bool =
  match xs with
  | [] -> ([], false)
  | x :: rest -> begin
      match
        List.find_map
          (fun y -> Option.map (fun r -> (y, r)) (resolve_or_pair x y))
          rest
      with
      | Some (y, resolved) ->
          let rest = List.filter (fun z -> key_of_hexpr z <> key_of_hexpr y) rest in
          (resolved :: rest, true)
      | None ->
          let rest, changed = resolve_or_once rest in
          (x :: rest, changed)
    end

let rec resolve_or_all xs =
  let xs, changed = resolve_or_once xs in
  if changed then resolve_or_all (dedup_hexprs xs) else xs

let conjunction_keys (h : hexpr) : string list =
  flatten_bool And h |> List.map key_of_hexpr |> List.sort_uniq String.compare

let keys_subset a b = List.for_all (fun x -> List.mem x b) a

let remove_absorbed_disjuncts (xs : hexpr list) : hexpr list =
  let keyed = List.map (fun h -> (h, conjunction_keys h)) xs in
  keyed
  |> List.filter (fun (h, keys) ->
         not
           (List.exists
              (fun (other, other_keys) ->
                key_of_hexpr h <> key_of_hexpr other && keys_subset other_keys keys)
              keyed))
  |> List.map fst

let rebuild_or_syntax (xs : hexpr list) : hexpr =
  let xs = List.concat_map (flatten_bool Or) xs in
  if List.exists is_htrue xs || or_has_tautology xs then htrue
  else
    let xs = xs |> List.filter (fun h -> not (is_hfalse h)) |> dedup_hexprs in
    let simple_terms =
      xs |> List.filter (fun h -> match flatten_bool And h with [ _ ] -> true | _ -> false)
    in
    let xs =
      List.fold_left
        (fun acc simple ->
          acc |> List.filter_map (simplify_disjunct_against_simple simple) |> dedup_hexprs)
        xs simple_terms
      |> resolve_or_all
      |> remove_absorbed_disjuncts
      |> dedup_hexprs
    in
    match xs with
    | [] -> hfalse
    | [ x ] -> x
    | x :: rest -> List.fold_left Core_syntax_builders.mk_hor x rest

let rec simplify_fo_syntax (f : Core_syntax.hexpr) : Core_syntax.hexpr =
  match f.hexpr with
  | HLitInt _ | HLitBool _ | HLitEnum _ | HVar _ | HPreK _ | HPred _ -> f
  | HUn (Neg, inner) -> mk_h (HUn (Neg, simplify_fo_syntax inner))
  | HUn (Not, inner) -> begin
      match (simplify_fo_syntax inner).hexpr with
      | HLitBool b -> Core_syntax_builders.mk_hbool (not b)
      | HUn (Not, nested) -> nested
      | HCmp (op, a, b) -> simplify_fo_syntax (mk_h (HCmp (negate_relop op, a, b)))
      | HBin (And, a, b) ->
          rebuild_or_syntax
            [ simplify_fo_syntax (Core_syntax_builders.mk_hnot a);
              simplify_fo_syntax (Core_syntax_builders.mk_hnot b) ]
      | HBin (Or, a, b) ->
          rebuild_and_syntax
            [ simplify_fo_syntax (Core_syntax_builders.mk_hnot a);
              simplify_fo_syntax (Core_syntax_builders.mk_hnot b) ]
      | simplified -> mk_h (HUn (Not, { f with hexpr = simplified }))
    end
  | HBin (And, a, b) -> rebuild_and_syntax [ simplify_fo_syntax a; simplify_fo_syntax b ]
  | HBin (Or, a, b) -> rebuild_or_syntax [ simplify_fo_syntax a; simplify_fo_syntax b ]
  | HBin (op, a, b) -> mk_h (HBin (op, simplify_fo_syntax a, simplify_fo_syntax b))
  | HCmp (op, a, b) ->
      let a = simplify_fo_syntax a in
      let b = simplify_fo_syntax b in
      begin
        match eval_const_rel op a b with
        | Some value -> Core_syntax_builders.mk_hbool value
        | None when a = b ->
            Core_syntax_builders.mk_hbool (match op with REq | RLe | RGe -> true | RNeq | RLt | RGt -> false)
        | None -> begin
            match (op, a.hexpr, b.hexpr) with
            | REq, _, HLitBool true -> a
            | REq, HLitBool true, _ -> b
            | RNeq, _, HLitBool true ->
                simplify_fo_syntax (Core_syntax_builders.mk_hnot a)
            | RNeq, HLitBool true, _ ->
                simplify_fo_syntax (Core_syntax_builders.mk_hnot b)
            | REq, _, HLitBool false ->
                simplify_fo_syntax (Core_syntax_builders.mk_hnot a)
            | REq, HLitBool false, _ ->
                simplify_fo_syntax (Core_syntax_builders.mk_hnot b)
            | RNeq, _, HLitBool false -> a
            | RNeq, HLitBool false, _ -> b
            | _ -> mk_h (HCmp (op, a, b))
          end
      end

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

let unify_var_sort (vars : (ident, smt_sort) Hashtbl.t) v s =
  match Hashtbl.find_opt vars v with
  | None ->
      Hashtbl.add vars v s;
      Some s
  | Some s' -> Some s'

let rec infer_expr_sort (vars : (ident, smt_sort) Hashtbl.t) (e : expr) : smt_sort option =
  match e.expr with
  | ELitInt _ -> Some SInt
  | ELitBool _ -> Some SBool
  | ELitEnum _ -> None
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
      (match a.expr with EVar v -> ignore (unify_var_sort vars v operand_sort) | _ -> ());
      (match b.expr with EVar v -> ignore (unify_var_sort vars v operand_sort) | _ -> ());
      Some SBool
    end

let rec infer_hexpr_sort vars (h : hexpr) =
  match h.hexpr with
  | HLitInt _ -> Some SInt
  | HLitBool _ -> Some SBool
  | HLitEnum _ -> None
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
      let operand_sort =
        match (sa, sb) with Some s, _ | _, Some s -> s | None, None -> SInt
      in
      let remember_operand_sort = function
        | { hexpr = HVar v; _ } | { hexpr = HPreK (v, _); _ } ->
            ignore (unify_var_sort vars v operand_sort)
        | _ -> ()
      in
      remember_operand_sort a;
      remember_operand_sort b;
      Some SBool
    end

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
  | ELitEnum _ -> raise Unsupported_enum_formula
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
  | HLitEnum _ -> raise Unsupported_enum_formula
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
  match e.expr with ELitInt _ | ELitBool _ | ELitEnum _ -> true | _ -> false

let is_const_hexpr (h : hexpr) =
  match h.hexpr with HLitInt _ | HLitBool _ | HLitEnum _ -> true | _ -> false

let flip_relop = function
  | REq -> REq
  | RNeq -> RNeq
  | RLt -> RGt
  | RLe -> RGe
  | RGt -> RLt
  | RGe -> RLe

let normalize_rel (h1 : hexpr) (r : relop) (h2 : hexpr) : ltl_atom =
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
    let syntactic = simplify_fo_syntax f in
    let t0 = Unix.gettimeofday () in
    let finish out =
      External_timing.record_z3 ~elapsed_s:(Unix.gettimeofday () -. t0);
      out
    in
    try
      let env = make_z3_env syntactic in
      let e0 = z3_of_fo env syntactic in
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
      finish (match fo_of_z3_formula env e2 with Some out -> Some out | None -> Some syntactic)
    with _ -> finish (Some syntactic)
