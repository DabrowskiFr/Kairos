(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 * Copyright (C) 2026 Frederic Dabrowski
 *
 * This program is free software: you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or
 * (at your option) any later version.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *---------------------------------------------------------------------------*)

open Kr_lang_surface.Kr_lang_surface_ast

(* Internal module used by the elaboration pipeline. *)
module S = Kr_lang_surface.Kr_lang_surface_ast

let subst_ident ~(param : string) ~(value : string) id =
  if String.equal id param then value else id

let nat_literal_of_ident id =
  match int_of_string_opt id with
  | Some n when n >= 0 -> Some n
  | _ -> None

let subst_ref ~(param : string) ~(value : string) (r : S.indexed_ref) :
    S.indexed_ref =
  {
    S.ref_base = subst_ident ~param ~value r.ref_base;
    ref_indices = List.map (subst_ident ~param ~value) r.ref_indices;
  }

let subst_nat_expr ~(param : string) ~(value : string) = function
  | SNNat _ as n -> n
  | SNVar id when String.equal id param -> (
      match nat_literal_of_ident value with
      | Some n -> SNNat n
      | None -> SNVar value)
  | SNVar id -> SNVar id

let rec subst_expr ~(param : string) ~(value : string) (e : S.expr) : S.expr =
  let sexpr =
    match e.sexpr with
    | SELitInt _ | SELitBool _ -> e.sexpr
    | SEVar r -> SEVar (subst_ref ~param ~value r)
    | SEPre r -> SEPre (subst_ref ~param ~value r)
    | SECall (callee, args) ->
        SECall (callee, List.map (subst_expr ~param ~value) args)
    | SEBin (op, a, b) ->
        SEBin (op, subst_expr ~param ~value a, subst_expr ~param ~value b)
    | SECmp (op, a, b) ->
        SECmp (op, subst_expr ~param ~value a, subst_expr ~param ~value b)
    | SEUn (op, inner) -> SEUn (op, subst_expr ~param ~value inner)
  in
  { e with sexpr }

let rec subst_hexpr ~(param : string) ~(value : string) (h : S.hexpr) :
    S.hexpr =
  let shexpr =
    match h.shexpr with
    | SHLitInt _ | SHLitBool _ -> h.shexpr
    | SHVar r -> SHVar (subst_ref ~param ~value r)
    | SHPreK (r, k) -> SHPreK (subst_ref ~param ~value r, subst_nat_expr ~param ~value k)
    | SHPast (inner, k) ->
        SHPast (subst_hexpr ~param ~value inner, subst_nat_expr ~param ~value k)
    | SHOld inner -> SHOld (subst_hexpr ~param ~value inner)
    | SHHistoryAlias (alias, r) ->
        SHHistoryAlias (alias, subst_ref ~param ~value r)
    | SHCall (callee, args) ->
        SHCall (callee, List.map (subst_hexpr ~param ~value) args)
    | SHExpr e -> SHExpr (subst_expr ~param ~value e)
    | SHBin (op, a, b) ->
        SHBin (op, subst_hexpr ~param ~value a, subst_hexpr ~param ~value b)
    | SHCmp (op, a, b) ->
        SHCmp (op, subst_hexpr ~param ~value a, subst_hexpr ~param ~value b)
    | SHUn (op, inner) -> SHUn (op, subst_hexpr ~param ~value inner)
    | SHForall (bound, enum_name, body) when String.equal bound param ->
        SHForall (bound, enum_name, body)
    | SHExists (bound, enum_name, body) when String.equal bound param ->
        SHExists (bound, enum_name, body)
    | SHForall (bound, enum_name, body) ->
        SHForall (bound, enum_name, subst_hexpr ~param ~value body)
    | SHExists (bound, enum_name, body) ->
        SHExists (bound, enum_name, subst_hexpr ~param ~value body)
    | SHRangeForall (bound, lo, hi, body) when String.equal bound param ->
        SHRangeForall
          (bound, subst_nat_expr ~param ~value lo, subst_nat_expr ~param ~value hi, body)
    | SHRangeExists (bound, lo, hi, body) when String.equal bound param ->
        SHRangeExists
          (bound, subst_nat_expr ~param ~value lo, subst_nat_expr ~param ~value hi, body)
    | SHRangeForall (bound, lo, hi, body) ->
        SHRangeForall
          ( bound,
            subst_nat_expr ~param ~value lo,
            subst_nat_expr ~param ~value hi,
            subst_hexpr ~param ~value body )
    | SHRangeExists (bound, lo, hi, body) ->
        SHRangeExists
          ( bound,
            subst_nat_expr ~param ~value lo,
            subst_nat_expr ~param ~value hi,
            subst_hexpr ~param ~value body )
  in
  { h with shexpr }

let rec subst_spec_arg ~(param : string) ~(value : string) = function
  | SAFormula f -> SAFormula (subst_ltl ~param ~value f)
  | SAHExpr h -> SAHExpr (subst_hexpr ~param ~value h)

and subst_ltl ~(param : string) ~(value : string) (f : S.ltl) : S.ltl =
  match f with
  | SLTrue | SLFalse -> f
  | SLAtom (a, op, b) ->
      SLAtom (subst_hexpr ~param ~value a, op, subst_hexpr ~param ~value b)
  | SLFo h -> SLFo (subst_hexpr ~param ~value h)
  | SLFormulaParam id -> SLFormulaParam (subst_ident ~param ~value id)
  | SLCall (callee, args) ->
      SLCall (callee, List.map (subst_spec_arg ~param ~value) args)
  | SLNot inner -> SLNot (subst_ltl ~param ~value inner)
  | SLAnd (a, b) -> SLAnd (subst_ltl ~param ~value a, subst_ltl ~param ~value b)
  | SLOr (a, b) -> SLOr (subst_ltl ~param ~value a, subst_ltl ~param ~value b)
  | SLImp (a, b) -> SLImp (subst_ltl ~param ~value a, subst_ltl ~param ~value b)
  | SLX inner -> SLX (subst_ltl ~param ~value inner)
  | SLG inner -> SLG (subst_ltl ~param ~value inner)
  | SLW (a, b) -> SLW (subst_ltl ~param ~value a, subst_ltl ~param ~value b)
  | SLForall (bound, enum_name, body) when String.equal bound param ->
      SLForall (bound, enum_name, body)
  | SLExists (bound, enum_name, body) when String.equal bound param ->
      SLExists (bound, enum_name, body)
  | SLForall (bound, enum_name, body) ->
      SLForall (bound, enum_name, subst_ltl ~param ~value body)
  | SLExists (bound, enum_name, body) ->
      SLExists (bound, enum_name, subst_ltl ~param ~value body)
  | SLRangeForall (bound, lo, hi, body) when String.equal bound param ->
      SLRangeForall
        (bound, subst_nat_expr ~param ~value lo, subst_nat_expr ~param ~value hi, body)
  | SLRangeExists (bound, lo, hi, body) when String.equal bound param ->
      SLRangeExists
        (bound, subst_nat_expr ~param ~value lo, subst_nat_expr ~param ~value hi, body)
  | SLRangeForall (bound, lo, hi, body) ->
      SLRangeForall
        ( bound,
          subst_nat_expr ~param ~value lo,
          subst_nat_expr ~param ~value hi,
          subst_ltl ~param ~value body )
  | SLRangeExists (bound, lo, hi, body) ->
      SLRangeExists
        ( bound,
          subst_nat_expr ~param ~value lo,
          subst_nat_expr ~param ~value hi,
          subst_ltl ~param ~value body )

let rec subst_stmt ~(param : string) ~(value : string) (s : S.stmt) : S.stmt =
  let sstmt =
    match s.sstmt with
    | SSAssign (lhs, rhs) ->
        SSAssign (subst_ref ~param ~value lhs, subst_expr ~param ~value rhs)
    | SSIf (cond, t, e) ->
        SSIf
          ( subst_expr ~param ~value cond,
            List.map (subst_stmt ~param ~value) t,
            List.map (subst_stmt ~param ~value) e )
    | SSWhile (cond, invariants, variant, body) ->
        SSWhile
          ( subst_expr ~param ~value cond,
            List.map (subst_hexpr ~param ~value) invariants,
            Option.map (subst_expr ~param ~value) variant,
            List.map (subst_stmt ~param ~value) body )
    | SSMatch (scrutinee, branches, dflt) ->
        SSMatch
          ( subst_expr ~param ~value scrutinee,
            List.map
              (fun (ctor, body) -> (ctor, List.map (subst_stmt ~param ~value) body))
              branches,
            Option.map (List.map (subst_stmt ~param ~value)) dflt )
    | SSSkip -> SSSkip
    | SSMethodCall (callee, args) ->
        SSMethodCall (callee, List.map (subst_expr ~param ~value) args)
    | SSFor (bound, enum_name, body) when String.equal bound param ->
        SSFor (bound, enum_name, body)
    | SSFor (bound, enum_name, body) ->
        SSFor (bound, enum_name, List.map (subst_stmt ~param ~value) body)
    | SSForRange (bound, lo, hi, body) when String.equal bound param ->
        SSForRange
          (bound, subst_nat_expr ~param ~value lo, subst_nat_expr ~param ~value hi, body)
    | SSForRange (bound, lo, hi, body) ->
        SSForRange
          ( bound,
            subst_nat_expr ~param ~value lo,
            subst_nat_expr ~param ~value hi,
            List.map (subst_stmt ~param ~value) body )
  in
  { s with sstmt }

(* [action_actual_error param usage] implements the internal action actual error operation. It returns the operation result. *)
let action_actual_error param usage =
  Kr_lang_shared.Kr_lang_shared_error.elaboration
    (Printf.sprintf
       "method parameter '%s' is used as %s and therefore requires a variable reference argument"
       param usage)

(* [actual_ref ~(param : string) ~(usage : string) (actual : S.expr)] implements the internal actual ref operation. It returns the operation result. *)
let actual_ref ~(param : string) ~(usage : string) (actual : S.expr) =
  match actual.sexpr with
  | SEVar r -> r
  | _ -> action_actual_error param usage

(* [actual_scalar_name ~(param : string) ~(usage : string) (actual : S.expr)] implements the internal actual scalar name operation. It returns the operation result. *)
let actual_scalar_name ~(param : string) ~(usage : string) (actual : S.expr) =
  match actual_ref ~param ~usage actual with
  | { ref_base; ref_indices = [] } -> ref_base
  | _ -> action_actual_error param usage

(* [subst_ref_expr ~(param : string) ~(actual : S.expr) (r : S.indexed_ref) :] transforms subst ref expr. It returns the transformed representation. *)
let subst_ref_expr ~(param : string) ~(actual : S.expr) (r : S.indexed_ref) :
    S.indexed_ref =
  if String.equal r.ref_base param then
    match r.ref_indices with
    | [] -> actual_ref ~param ~usage:"an assignment destination" actual
    | _ ->
        Kr_lang_shared.Kr_lang_shared_error.elaboration
          (Printf.sprintf
             "method parameter '%s' cannot be used as the base of an indexed variable"
             param)
  else
    let ref_indices =
      List.map
        (fun index ->
          if String.equal index param then
            actual_scalar_name ~param ~usage:"a static array index" actual
          else index)
        r.ref_indices
    in
    { r with ref_indices }

(* [subst_nat_expr_expr ~(param : string) ~(actual : S.expr)] transforms subst nat expr expr. It returns the transformed representation. *)
let subst_nat_expr_expr ~(param : string) ~(actual : S.expr) = function
  | SNNat _ as n -> n
  | SNVar id when String.equal id param -> (
      match actual.sexpr with
      | SELitInt n when n >= 0 -> SNNat n
      | SEVar { ref_base; ref_indices = [] } -> SNVar ref_base
      | _ ->
          Kr_lang_shared.Kr_lang_shared_error.elaboration
            (Printf.sprintf
               "method parameter '%s' is used as a static natural number and requires a non-negative literal or scalar name"
               param))
  | SNVar id -> SNVar id

let rec subst_expr_actual ~(param : string) ~(actual : S.expr) (e : S.expr) :
    S.expr =
  match e.sexpr with
  | SEVar { ref_base; ref_indices = [] } when String.equal ref_base param ->
      actual
  | _ ->
      let sexpr =
        match e.sexpr with
        | SELitInt _ | SELitBool _ -> e.sexpr
        | SEVar r -> SEVar (subst_ref_expr ~param ~actual r)
        | SEPre r -> SEPre (subst_ref_expr ~param ~actual r)
        | SECall (callee, args) ->
            SECall
              (callee, List.map (subst_expr_actual ~param ~actual) args)
        | SEBin (op, a, b) ->
            SEBin
              ( op,
                subst_expr_actual ~param ~actual a,
                subst_expr_actual ~param ~actual b )
        | SECmp (op, a, b) ->
            SECmp
              ( op,
                subst_expr_actual ~param ~actual a,
                subst_expr_actual ~param ~actual b )
        | SEUn (op, inner) ->
            SEUn (op, subst_expr_actual ~param ~actual inner)
      in
      { e with sexpr }

let rec subst_hexpr_actual ~(param : string) ~(actual : S.expr)
    (h : S.hexpr) : S.hexpr =
  match h.shexpr with
  | SHVar { ref_base; ref_indices = [] } when String.equal ref_base param ->
      { h with shexpr = SHExpr actual }
  | _ ->
      let shexpr =
        match h.shexpr with
        | SHLitInt _ | SHLitBool _ -> h.shexpr
        | SHVar r -> SHVar (subst_ref_expr ~param ~actual r)
        | SHPreK (r, k) ->
            SHPreK
              ( subst_ref_expr ~param ~actual r,
                subst_nat_expr_expr ~param ~actual k )
        | SHPast (inner, k) ->
            SHPast
              ( subst_hexpr_actual ~param ~actual inner,
                subst_nat_expr_expr ~param ~actual k )
        | SHOld inner -> SHOld (subst_hexpr_actual ~param ~actual inner)
        | SHHistoryAlias (alias, r) ->
            SHHistoryAlias (alias, subst_ref_expr ~param ~actual r)
        | SHCall (callee, args) ->
            SHCall
              (callee, List.map (subst_hexpr_actual ~param ~actual) args)
        | SHExpr e -> SHExpr (subst_expr_actual ~param ~actual e)
        | SHBin (op, a, b) ->
            SHBin
              ( op,
                subst_hexpr_actual ~param ~actual a,
                subst_hexpr_actual ~param ~actual b )
        | SHCmp (op, a, b) ->
            SHCmp
              ( op,
                subst_hexpr_actual ~param ~actual a,
                subst_hexpr_actual ~param ~actual b )
        | SHUn (op, inner) ->
            SHUn (op, subst_hexpr_actual ~param ~actual inner)
        | SHForall (bound, enum_name, body)
          when String.equal bound param ->
            SHForall (bound, enum_name, body)
        | SHExists (bound, enum_name, body)
          when String.equal bound param ->
            SHExists (bound, enum_name, body)
        | SHForall (bound, enum_name, body) ->
            SHForall
              (bound, enum_name, subst_hexpr_actual ~param ~actual body)
        | SHExists (bound, enum_name, body) ->
            SHExists
              (bound, enum_name, subst_hexpr_actual ~param ~actual body)
        | SHRangeForall (bound, lo, hi, body)
          when String.equal bound param ->
            SHRangeForall
              ( bound,
                subst_nat_expr_expr ~param ~actual lo,
                subst_nat_expr_expr ~param ~actual hi,
                body )
        | SHRangeExists (bound, lo, hi, body)
          when String.equal bound param ->
            SHRangeExists
              ( bound,
                subst_nat_expr_expr ~param ~actual lo,
                subst_nat_expr_expr ~param ~actual hi,
                body )
        | SHRangeForall (bound, lo, hi, body) ->
            SHRangeForall
              ( bound,
                subst_nat_expr_expr ~param ~actual lo,
                subst_nat_expr_expr ~param ~actual hi,
                subst_hexpr_actual ~param ~actual body )
        | SHRangeExists (bound, lo, hi, body) ->
            SHRangeExists
              ( bound,
                subst_nat_expr_expr ~param ~actual lo,
                subst_nat_expr_expr ~param ~actual hi,
                subst_hexpr_actual ~param ~actual body )
      in
      { h with shexpr }

let rec subst_stmt_actual ~(param : string) ~(actual : S.expr) (s : S.stmt) :
    S.stmt =
  let sstmt =
    match s.sstmt with
    | SSAssign (lhs, rhs) ->
        SSAssign
          ( subst_ref_expr ~param ~actual lhs,
            subst_expr_actual ~param ~actual rhs )
    | SSIf (cond, then_branch, else_branch) ->
        SSIf
          ( subst_expr_actual ~param ~actual cond,
            List.map (subst_stmt_actual ~param ~actual) then_branch,
            List.map (subst_stmt_actual ~param ~actual) else_branch )
    | SSWhile (cond, invariants, variant, body) ->
        SSWhile
          ( subst_expr_actual ~param ~actual cond,
            List.map (subst_hexpr_actual ~param ~actual) invariants,
            Option.map (subst_expr_actual ~param ~actual) variant,
            List.map (subst_stmt_actual ~param ~actual) body )
    | SSMatch (scrutinee, branches, default_branch) ->
        SSMatch
          ( subst_expr_actual ~param ~actual scrutinee,
            List.map
              (fun (ctor, body) ->
                (ctor, List.map (subst_stmt_actual ~param ~actual) body))
              branches,
            Option.map (List.map (subst_stmt_actual ~param ~actual)) default_branch )
    | SSSkip -> SSSkip
    | SSMethodCall (callee, args) ->
        SSMethodCall
          (callee, List.map (subst_expr_actual ~param ~actual) args)
    | SSFor (bound, enum_name, body) when String.equal bound param ->
        SSFor (bound, enum_name, body)
    | SSFor (bound, enum_name, body) ->
        SSFor
          ( bound,
            enum_name,
            List.map (subst_stmt_actual ~param ~actual) body )
    | SSForRange (bound, lo, hi, body)
      when String.equal bound param ->
        SSForRange
          ( bound,
            subst_nat_expr_expr ~param ~actual lo,
            subst_nat_expr_expr ~param ~actual hi,
            body )
    | SSForRange (bound, lo, hi, body) ->
        SSForRange
          ( bound,
            subst_nat_expr_expr ~param ~actual lo,
            subst_nat_expr_expr ~param ~actual hi,
            List.map (subst_stmt_actual ~param ~actual) body )
  in
  { s with sstmt }

let rec subst_history_expr ~(param : string) ~(value : string)
    (h : S.history_expr) : S.history_expr =
  let shistory_expr =
    match h.shistory_expr with
    | SHValue formula -> SHValue (subst_hexpr ~param ~value formula)
    | SHIf (cond, then_value, else_value) ->
        SHIf
          ( subst_hexpr ~param ~value cond,
            subst_history_expr ~param ~value then_value,
            subst_history_expr ~param ~value else_value )
  in
  { h with shistory_expr }
