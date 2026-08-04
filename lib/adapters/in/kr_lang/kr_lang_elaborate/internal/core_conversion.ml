(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 *---------------------------------------------------------------------------*)

(* Convert normalized historical formulas to executable and temporal Core AST. *)
open Kr_lang_surface.Kr_lang_surface_syntax
open Kr_lang_core.Kr_lang_core_syntax
open Env

module B = Kr_lang_core.Kr_lang_core_syntax_builders
module S = Kr_lang_surface.Kr_lang_surface_syntax

let rec ltl_of_fo (h : hexpr) : ltl =
  match h.hexpr with
  | HLitBool true -> LTrue
  | HLitBool false -> LFalse
  | HUn (Not, inner) -> LNot (ltl_of_fo inner)
  | HBin (And, a, b) -> LAnd (ltl_of_fo a, ltl_of_fo b)
  | HBin (Or, a, b) -> LOr (ltl_of_fo a, ltl_of_fo b)
  | HCmp (op, a, b) -> LAtom (a, op, b)
  | _ -> LAtom (h, REq, B.mk_hbool true)

(* [expr_of_fo (h : hexpr) : expr] implements the internal expr of fo operation. It returns the operation result. *)
let rec expr_of_fo (h : hexpr) : expr =
  let expr =
    match h.hexpr with
    | HLitInt n -> ELitInt n
    | HLitBool b -> ELitBool b
    | HVar id -> EVar id
    | HOld _ ->
        Kr_lang_shared.Kr_lang_shared_error.elaboration "old cannot be used in executable expressions"
    | HPreK _ -> Kr_lang_shared.Kr_lang_shared_error.elaboration "historical predicate cannot be used in executable expressions"
    | HPred _ -> Kr_lang_shared.Kr_lang_shared_error.elaboration "unexpanded predicate cannot be used in executable expressions"
    | HFunCall (fn, args) -> EFunCall (fn, List.map expr_of_fo args)
    | HBin (op, a, b) -> EBin (op, expr_of_fo a, expr_of_fo b)
    | HCmp (op, a, b) -> ECmp (op, expr_of_fo a, expr_of_fo b)
    | HUn (op, inner) -> EUn (op, expr_of_fo inner)
  in
  { expr; loc = h.loc }

(* [core_ltl_and] implements the internal core ltl and operation. It returns the operation result. *)
let rec core_ltl_and = function
  | [] -> LTrue
  | [ x ] -> x
  | x :: xs -> LAnd (x, core_ltl_and xs)

(* [core_ltl_or] implements the internal core ltl or operation. It returns the operation result. *)
let rec core_ltl_or = function
  | [] -> LFalse
  | [ x ] -> x
  | x :: xs -> LOr (x, core_ltl_or xs)

(* [core_hexpr_and] implements the internal core hexpr and operation. It returns the operation result. *)
let rec core_hexpr_and = function
  | [] -> B.mk_hbool true
  | [ x ] -> x
  | x :: xs -> B.mk_hand x (core_hexpr_and xs)

(* [core_hexpr_or] implements the internal core hexpr or operation. It returns the operation result. *)
let rec core_hexpr_or = function
  | [] -> B.mk_hbool false
  | [ x ] -> x
  | x :: xs -> B.mk_hor x (core_hexpr_or xs)

(* [type_error context message] computes type error. It returns the computed result. *)
