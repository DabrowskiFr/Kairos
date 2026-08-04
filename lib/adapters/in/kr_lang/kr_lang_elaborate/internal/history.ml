(*---------------------------------------------------------------------------
 * Kairos - deductive verification for synchronous programs
 *---------------------------------------------------------------------------*)

(* Resolve and normalize history operators and their specification arguments. *)
open Kr_lang_surface.Kr_lang_surface_syntax
open Kr_lang_core.Kr_lang_core_syntax
open Env

module B = Kr_lang_core.Kr_lang_core_syntax_builders
module S = Kr_lang_surface.Kr_lang_surface_syntax

(* Test whether [r] names [name] without indices. *)
let is_scalar_ref_named name (r : S.indexed_ref) =
  String.equal r.ref_base name && r.ref_indices = []

(* [ref_with_nat_params ctx (r : S.indexed_ref) : S.indexed_ref] implements the internal ref with nat params operation. It returns the operation result. *)
let ref_with_nat_params ctx (r : S.indexed_ref) : S.indexed_ref =
  let resolve_index id =
    match List.assoc_opt id ctx.nat_params with
    | Some n -> string_of_int n
    | None -> id
  in
  { r with ref_indices = List.map resolve_index r.ref_indices }

(* [scalar_nat_value ctx (r : S.indexed_ref) : int option] implements the internal scalar nat value operation. It returns the operation result. *)
let scalar_nat_value ctx (r : S.indexed_ref) : int option =
  match r.ref_indices with
  | [] -> (
      match List.assoc_opt r.ref_base ctx.nat_params with
      | Some n -> Some n
      | None -> Subst.nat_literal_of_ident r.ref_base)
  | _ -> None

(* Resolve a parameterized source reference before applying history. *)
let resolve_history_source_ref ctx (r : S.indexed_ref) =
  let r = ref_with_nat_params ctx r in
  match (r.ref_indices, List.assoc_opt r.ref_base ctx.hexpr_params) with
  | [], Some { shexpr = SHVar actual; _ } -> actual
  | [], Some _ ->
      Kr_lang_shared.Kr_lang_shared_error.elaboration
        (Printf.sprintf
           "historical expression operator expects variable argument '%s' to be a variable reference"
           r.ref_base)
  | _ -> r

(* [normalize_history_shift k h] combines nested historical offsets in [h]
   and returns an equivalent core expression with one normalized offset. *)
let rec normalize_history_shift k (h : hexpr) : hexpr =
  if k < 0 then
    Kr_lang_shared.Kr_lang_shared_error.well_formedness "past offset must be non-negative";
  if k = 0 then h
  else
    let mk desc = B.mk_hexpr ?loc:h.loc desc in
    match h.hexpr with
    | HLitInt _ | HLitBool _ -> h
    | HVar v -> mk (HPreK (v, k))
    | HOld _ ->
        Kr_lang_shared.Kr_lang_shared_error.elaboration
          "old is only allowed in method postconditions"
    | HPreK (v, j) -> mk (HPreK (v, j + k))
    | HPred (name, args) -> mk (HPred (name, List.map (normalize_history_shift k) args))
    | HFunCall (name, args) -> mk (HFunCall (name, List.map (normalize_history_shift k) args))
    | HBin (op, a, b) -> mk (HBin (op, normalize_history_shift k a, normalize_history_shift k b))
    | HCmp (op, a, b) -> mk (HCmp (op, normalize_history_shift k a, normalize_history_shift k b))
    | HUn (op, inner) -> mk (HUn (op, normalize_history_shift k inner))

(* [implicit_history_alias_k (alias : string) : int option] implements the internal implicit history alias k operation. It returns the operation result. *)
let implicit_history_alias_k (alias : string) : int option =
  let prefix = "prev" in
  let plen = String.length prefix in
  if String.length alias < plen then None
  else if not (String.starts_with ~prefix alias) then None
  else
    let suffix = String.sub alias plen (String.length alias - plen) in
    if String.length suffix = 0 then Some 1
    else
      let all_digits =
        let rec loop i =
          if i >= String.length suffix then true
          else
            match suffix.[i] with
            | '0' .. '9' -> loop (i + 1)
            | _ -> false
        in
        loop 0
      in
      if not all_digits then None
      else
        let k = int_of_string suffix in
        if k < 1 then None else Some k

(* [expand_history_alias env alias arg] transforms expand history alias. It returns the transformed representation. *)
let expand_history_alias env alias arg =
  match List.assoc_opt alias env.history_aliases with
  | Some (_param, k) -> B.mk_hpre_k arg k
  | None -> (
      match implicit_history_alias_k alias with
      | Some k -> B.mk_hpre_k arg k
      | None -> Kr_lang_shared.Kr_lang_shared_error.elaboration (Printf.sprintf "unknown history alias '%s'" alias))

(* [formula_arg_of_spec_arg _ctx] implements the internal formula arg of spec arg operation. It returns the operation result. *)
(* Extract a formula argument and reject expressions in that position. *)
let formula_arg_of_spec_arg _ctx = function
  | SAFormula f -> f
  | SAHExpr _ -> Kr_lang_shared.Kr_lang_shared_error.elaboration "Formula parameter expects a formula argument"

(* [hexpr_arg_of_spec_arg ctx] implements the internal hexpr arg of spec arg operation. It returns the operation result. *)
(* Resolve an historical-expression specification argument. *)
let hexpr_arg_of_spec_arg ctx = function
  | SAHExpr ({ shexpr = SHVar { ref_base; ref_indices = [] }; _ }) as arg -> (
      match List.assoc_opt ref_base ctx.hexpr_params with
      | Some h -> h
      | None -> (
          match arg with SAHExpr h -> h | SAFormula _ -> assert false))
  | SAHExpr h -> h
  | SAFormula _ -> Kr_lang_shared.Kr_lang_shared_error.elaboration "HExpr parameter expects a historical expression argument"

(* [nat_arg_of_spec_arg ctx] implements the internal nat arg of spec arg operation. It returns the operation result. *)
(* Evaluate a natural-number specification argument. *)
let nat_arg_of_spec_arg ctx = function
  | SAHExpr { shexpr = SHLitInt n; _ } ->
      if n < 0 then
        Kr_lang_shared.Kr_lang_shared_error.well_formedness
          "Nat parameter expects a non-negative integer";
      n
  | SAHExpr { shexpr = SHVar { ref_base; ref_indices = [] }; _ } -> eval_nat ctx (SNVar ref_base)
  | _ -> Kr_lang_shared.Kr_lang_shared_error.elaboration "Nat parameter expects an integer literal or Nat parameter"
