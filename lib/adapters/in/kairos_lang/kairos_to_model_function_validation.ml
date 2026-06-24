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

let validate_function_decls (type_decls : Core_syntax.enum_decl list)
    (function_decls : Core_syntax.pure_function_decl list) : unit =
  let fail_function fname msg =
    failwith (Printf.sprintf "Type error in function %s: %s" fname msg)
  in
  let function_names = Hashtbl.create (List.length function_decls * 2 + 1) in
  List.iter
    (fun (f : Core_syntax.pure_function_decl) ->
      if String.equal f.function_name "result" then
        fail_function f.function_name "'result' is reserved for function postconditions";
      match Hashtbl.find_opt function_names f.function_name with
      | Some () -> fail_function f.function_name "duplicate pure function"
      | None -> Hashtbl.add function_names f.function_name ())
    function_decls;
  let function_sigs =
    List.map
      (fun (f : Core_syntax.pure_function_decl) ->
        (f.function_name, (f.function_params, f.function_return)))
      function_decls
  in
  let find_ctor fname c =
    match lookup_constructor type_decls c with
    | Some ty -> ty
    | None -> fail_function fname (Printf.sprintf "unknown enum constructor '%s'" c)
  in
  let find_fun fname called =
    match List.assoc_opt called function_sigs with
    | Some sig_ -> sig_
    | None -> fail_function fname (Printf.sprintf "unknown pure function '%s'" called)
  in
  let expect_ty fname context expected actual =
    if not (same_ty expected actual) then
      fail_function fname
        (Printf.sprintf "%s has type %s but %s was expected" context
           (type_name actual) (type_name expected))
  in
  let rec expr_ty fname var_types (e : Core_syntax.expr) : Core_syntax.ty =
    let find_var x =
      match List.assoc_opt x var_types with
      | Some ty -> ty
      | None -> fail_function fname (Printf.sprintf "unknown variable '%s'" x)
    in
    match e.expr with
    | ELitInt _ -> TInt
    | ELitBool _ -> TBool
    | ELitEnum c -> find_ctor fname c
    | EVar x -> find_var x
    | EFunCall (called, args) ->
        let params, return_ty = find_fun fname called in
        if List.length params <> List.length args then
          fail_function fname
            (Printf.sprintf "function '%s' expects %d arguments but got %d"
               called (List.length params) (List.length args));
        List.iter2
          (fun (param : Core_syntax.vdecl) arg ->
            expect_ty fname
              ("argument " ^ param.vname ^ " of function '" ^ called ^ "'")
              param.vty (expr_ty fname var_types arg))
          params args;
        return_ty
    | EUn (Not, inner) ->
        expect_ty fname "not operand" TBool (expr_ty fname var_types inner);
        TBool
    | EUn (Neg, inner) ->
        expect_ty fname "negation operand" TInt (expr_ty fname var_types inner);
        TInt
    | EBin ((And | Or), a, b) ->
        expect_ty fname "left boolean operand" TBool (expr_ty fname var_types a);
        expect_ty fname "right boolean operand" TBool (expr_ty fname var_types b);
        TBool
    | EBin ((Add | Sub | Mul | Div), a, b) ->
        expect_ty fname "left arithmetic operand" TInt (expr_ty fname var_types a);
        expect_ty fname "right arithmetic operand" TInt (expr_ty fname var_types b);
        TInt
    | ECmp ((REq | RNeq), a, b) ->
        let ta = expr_ty fname var_types a in
        let tb = expr_ty fname var_types b in
        if not (same_ty ta tb) then
          fail_function fname
            (Printf.sprintf "comparison mixes %s and %s" (type_name ta)
               (type_name tb));
        TBool
    | ECmp ((RLt | RLe | RGt | RGe), a, b) ->
        expect_ty fname "left ordered comparison operand" TInt
          (expr_ty fname var_types a);
        expect_ty fname "right ordered comparison operand" TInt
          (expr_ty fname var_types b);
        TBool
  in
  let rec hexpr_has_history (h : Core_syntax.hexpr) : bool =
    match h.hexpr with
    | HPreK _ -> true
    | HLitInt _ | HLitBool _ | HLitEnum _ | HVar _ -> false
    | HPred (_, hs) | HFunCall (_, hs) -> List.exists hexpr_has_history hs
    | HUn (_, inner) -> hexpr_has_history inner
    | HBin (_, a, b) | HCmp (_, a, b) ->
        hexpr_has_history a || hexpr_has_history b
  in
  let rec hexpr_ty fname var_types (h : Core_syntax.hexpr) : Core_syntax.ty =
    let find_var x =
      match List.assoc_opt x var_types with
      | Some ty -> ty
      | None -> fail_function fname (Printf.sprintf "unknown variable '%s'" x)
    in
    match h.hexpr with
    | HLitInt _ -> TInt
    | HLitBool _ -> TBool
    | HLitEnum c -> find_ctor fname c
    | HVar x -> find_var x
    | HPreK _ -> fail_function fname "function contracts cannot mention history"
    | HPred (id, _) ->
        fail_function fname
          (Printf.sprintf "function contracts cannot mention predicate '%s'" id)
    | HFunCall (called, args) ->
        let params, return_ty = find_fun fname called in
        if List.length params <> List.length args then
          fail_function fname
            (Printf.sprintf "function '%s' expects %d arguments but got %d"
               called (List.length params) (List.length args));
        List.iter2
          (fun (param : Core_syntax.vdecl) arg ->
            expect_ty fname
              ("argument " ^ param.vname ^ " of function '" ^ called ^ "'")
              param.vty (hexpr_ty fname var_types arg))
          params args;
        return_ty
    | HUn (Not, inner) ->
        expect_ty fname "not operand" TBool (hexpr_ty fname var_types inner);
        TBool
    | HUn (Neg, inner) ->
        expect_ty fname "negation operand" TInt (hexpr_ty fname var_types inner);
        TInt
    | HBin ((And | Or), a, b) ->
        expect_ty fname "left boolean operand" TBool (hexpr_ty fname var_types a);
        expect_ty fname "right boolean operand" TBool (hexpr_ty fname var_types b);
        TBool
    | HBin ((Add | Sub | Mul | Div), a, b) ->
        expect_ty fname "left arithmetic operand" TInt
          (hexpr_ty fname var_types a);
        expect_ty fname "right arithmetic operand" TInt
          (hexpr_ty fname var_types b);
        TInt
    | HCmp ((REq | RNeq), a, b) ->
        let ta = hexpr_ty fname var_types a in
        let tb = hexpr_ty fname var_types b in
        if not (same_ty ta tb) then
          fail_function fname
            (Printf.sprintf "formula comparison mixes %s and %s"
               (type_name ta) (type_name tb));
        TBool
    | HCmp ((RLt | RLe | RGt | RGe), a, b) ->
        expect_ty fname "left ordered formula operand" TInt
          (hexpr_ty fname var_types a);
        expect_ty fname "right ordered formula operand" TInt
          (hexpr_ty fname var_types b);
        TBool
  in
  List.iter
    (fun (f : Core_syntax.pure_function_decl) ->
      let seen_params = Hashtbl.create 8 in
      List.iter
        (fun (param : Core_syntax.vdecl) ->
          if String.equal param.vname "result" then
            fail_function f.function_name
              "function parameter 'result' is reserved for postconditions";
          match Hashtbl.find_opt seen_params param.vname with
          | Some () ->
              fail_function f.function_name
                (Printf.sprintf "duplicate parameter '%s'" param.vname)
          | None -> Hashtbl.add seen_params param.vname ())
        f.function_params;
      let param_types =
        List.map (fun (v : Core_syntax.vdecl) -> (v.vname, v.vty))
          f.function_params
      in
      expect_ty f.function_name "function body" f.function_return
        (expr_ty f.function_name param_types f.function_body);
      List.iter
        (fun req ->
          if hexpr_has_history req then
            fail_function f.function_name "function requires cannot mention history";
          expect_ty f.function_name "requires clause" TBool
            (hexpr_ty f.function_name param_types req))
        f.function_requires;
      let post_types = ("result", f.function_return) :: param_types in
      List.iter
        (fun ens ->
          if hexpr_has_history ens then
            fail_function f.function_name "function ensures cannot mention history";
          expect_ty f.function_name "ensures clause" TBool
            (hexpr_ty f.function_name post_types ens))
        f.function_ensures)
    function_decls
