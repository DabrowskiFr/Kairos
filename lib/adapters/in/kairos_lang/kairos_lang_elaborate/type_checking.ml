(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 *---------------------------------------------------------------------------*)

(* Infer and validate types after surface expressions have been lowered. *)
open Surface.Syntax
open Core.Syntax
open Env

module B = Core.Syntax_builders
module S = Surface.Syntax

(* Raise a consistently classified type error with its source context. *)
let type_error context message =
  Shared.Error.elaboration
    (Printf.sprintf "%s: %s" context message)

(* Check equality, allowing the language's integral widening rule. *)
let check_expected_type ~context expected actual =
  let integral = function
    | TInt -> true
    | TBool | TReal | TCustom _ -> false
  in
  if expected <> actual && not (integral expected && integral actual) then
    type_error context
      (Printf.sprintf "expected %s but got %s"
         (type_name expected) (type_name actual))

(* [value_type_exn env context name] implements the internal value type exn operation. It returns the operation result. *)
let value_type_exn env context name =
  match value_type env name with
  | Some ty -> ty
  | None ->
      type_error context (Printf.sprintf "unknown value '%s'" name)

(* [check_call_arguments ~context formals actual_types] checks call arguments. It returns normally when the check succeeds and raises a classified error otherwise. *)
let check_call_arguments ~context formals actual_types =
  if List.length formals <> List.length actual_types then
    type_error context
      (Printf.sprintf "expects %d arguments but got %d"
         (List.length formals) (List.length actual_types));
  List.iter2
    (fun (formal : vdecl) actual ->
      check_expected_type
        ~context:(Printf.sprintf "%s, argument '%s'" context formal.vname)
        formal.vty actual)
    formals actual_types

(* Infer executable expression types recursively and validate every call. *)
let rec infer_expr_type env (e : Core.Syntax.expr) =
  let context = "executable expression" in
  match e.expr with
  | ELitInt _ -> TInt
  | ELitBool _ -> TBool
  | EVar name -> value_type_exn env context name
  | EFunCall (name, args) -> (
      match function_sig env name with
      | None -> type_error context (Printf.sprintf "unknown function '%s'" name)
      | Some (formals, return_ty) ->
          check_call_arguments
            ~context:(Printf.sprintf "function '%s'" name)
            formals (List.map (infer_expr_type env) args);
          return_ty)
  | EBin ((Add | Sub | Mul | Div), left, right) ->
      let left_ty = infer_expr_type env left in
      let right_ty = infer_expr_type env right in
      check_expected_type ~context left_ty right_ty;
      let result_ty = if left_ty = TInt then right_ty else left_ty in
      (match result_ty with
      | TInt | TReal -> result_ty
      | TBool | TCustom _ ->
          type_error context "arithmetic operands must be numeric")
  | EBin ((And | Or), left, right) ->
      check_expected_type ~context TBool (infer_expr_type env left);
      check_expected_type ~context TBool (infer_expr_type env right);
      TBool
  | ECmp (_, left, right) ->
      let left_ty = infer_expr_type env left in
      check_expected_type ~context left_ty (infer_expr_type env right);
      TBool
  | EUn (Neg, inner) ->
      let inner_ty = infer_expr_type env inner in
      (match inner_ty with
      | TInt | TReal -> inner_ty
      | TBool | TCustom _ ->
          type_error context "unary minus expects a numeric operand")
  | EUn (Not, inner) ->
      check_expected_type ~context TBool (infer_expr_type env inner);
      TBool

(* Infer historical-expression types, including temporal wrappers. *)
let rec infer_hexpr_type env (h : Core.Syntax.hexpr) =
  let context = "historical expression" in
  match h.hexpr with
  | HLitInt _ -> TInt
  | HLitBool _ -> TBool
  | HVar name | HPreK (name, _) -> value_type_exn env context name
  | HOld inner -> infer_hexpr_type env inner
  | HPred (_, _) -> TBool
  | HFunCall (name, args) -> (
      match function_sig env name with
      | None -> type_error context (Printf.sprintf "unknown function '%s'" name)
      | Some (formals, return_ty) ->
          check_call_arguments
            ~context:(Printf.sprintf "function '%s'" name)
            formals (List.map (infer_hexpr_type env) args);
          return_ty)
  | HBin ((Add | Sub | Mul | Div), left, right) ->
      let left_ty = infer_hexpr_type env left in
      let right_ty = infer_hexpr_type env right in
      check_expected_type ~context left_ty right_ty;
      let result_ty = if left_ty = TInt then right_ty else left_ty in
      (match result_ty with
      | TInt | TReal -> result_ty
      | TBool | TCustom _ ->
          type_error context "arithmetic operands must be numeric")
  | HBin ((And | Or), left, right) ->
      check_expected_type ~context TBool (infer_hexpr_type env left);
      check_expected_type ~context TBool (infer_hexpr_type env right);
      TBool
  | HCmp (_, left, right) ->
      let left_ty = infer_hexpr_type env left in
      check_expected_type ~context left_ty (infer_hexpr_type env right);
      TBool
  | HUn (Neg, inner) ->
      let inner_ty = infer_hexpr_type env inner in
      (match inner_ty with
      | TInt | TReal -> inner_ty
      | TBool | TCustom _ ->
          type_error context "unary minus expects a numeric operand")
  | HUn (Not, inner) ->
      check_expected_type ~context TBool (infer_hexpr_type env inner);
      TBool
