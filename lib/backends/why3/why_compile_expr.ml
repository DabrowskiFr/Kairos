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

[@@@ocaml.warning "-8-26-27-32-33"]

open Why3
open Ptree
open Ast
open Ast_builders
open Generated_names
open Temporal_support
open Ast_pretty
open Why_term_support

let rec compile_iexpr (env : env) (e : iexpr) : Ptree.expr =
  match e.iexpr with
  | ILitInt n -> mk_expr (Econst (Constant.int_const (BigInt.of_int n)))
  | ILitBool b -> mk_expr (if b then Etrue else Efalse)
  | IVar x ->
      if is_rec_var env x then field env x else mk_expr (Eident (qid1 x))
  | IPar e -> compile_iexpr env e
  | IUn (Neg, a) -> mk_expr (Eidapp (qid1 "(-)", [ compile_iexpr env a ]))
  | IUn (Not, a) -> mk_expr (Enot (compile_iexpr env a))
  | IBin (op, a, b) ->
      mk_expr (Einnfix (compile_iexpr env a, infix_ident (binop_id op), compile_iexpr env b))

let rec compile_term (env : env) (e : iexpr) : Ptree.term =
  match e.iexpr with
  | ILitInt n -> mk_term (Tconst (Constant.int_const (BigInt.of_int n)))
  | ILitBool b -> mk_term (if b then Ttrue else Tfalse)
  | IVar x -> mk_term (term_var env x)
  | IPar e -> compile_term env e
  | IUn (Neg, a) -> mk_term (Tidapp (qid1 "(-)", [ compile_term env a ]))
  | IUn (Not, a) -> mk_term (Tnot (compile_term env a))
  | IBin (op, a, b) ->
      mk_term (Tinnfix (compile_term env a, infix_ident (binop_id op), compile_term env b))

let rec compile_term_instance (env : env) (inst_name : ident) (node_name : ident)
    (inputs : ident list) (e : iexpr) : Ptree.term =
  match e.iexpr with
  | ILitInt n -> mk_term (Tconst (Constant.int_const (BigInt.of_int n)))
  | ILitBool b -> mk_term (if b then Ttrue else Tfalse)
  | IVar x -> term_of_instance_var env inst_name node_name x
  | IPar e -> compile_term_instance env inst_name node_name inputs e
  | IUn (Neg, a) ->
      mk_term (Tidapp (qid1 "(-)", [ compile_term_instance env inst_name node_name inputs a ]))
  | IUn (Not, a) -> mk_term (Tnot (compile_term_instance env inst_name node_name inputs a))
  | IBin (op, a, b) ->
      mk_term
        (Tinnfix
           ( compile_term_instance env inst_name node_name inputs a,
             infix_ident (binop_id op),
             compile_term_instance env inst_name node_name inputs b ))

let compile_hexpr_instance_contract ?(in_post = false) (env : env) (inst_name : ident)
    (node_name : ident) (inputs : ident list)
    (contract : Kernel_guided_contract.exported_summary_contract) (h : hexpr) : Ptree.term =
  match h with
  | HNow e -> compile_term_instance env inst_name node_name inputs e
  | HPreK (_e, _) -> begin
      match Kernel_guided_contract.latest_slot_name_for_hexpr contract h with
      | None -> failwith "pre_k not registered in kernel-guided contract (instance)"
      | Some name -> term_of_instance_var env inst_name node_name name
    end

let compile_fo_term_instance_contract ?(in_post = false) (env : env) (inst_name : ident)
    (node_name : ident) (inputs : ident list)
    (contract : Kernel_guided_contract.exported_summary_contract) (f : fo_atom) : Ptree.term =
  match f with
  | FRel (h1, r, h2) ->
      mk_term
        (Tinnfix
           ( compile_hexpr_instance_contract ~in_post env inst_name node_name inputs contract h1,
             infix_ident (relop_id r),
             compile_hexpr_instance_contract ~in_post env inst_name node_name inputs contract h2 ))
  | FPred (id, hs) ->
      mk_term
        (Tidapp
           ( qid1 id,
             List.map
               (compile_hexpr_instance_contract ~in_post env inst_name node_name inputs contract)
               hs ))

let rec compile_ltl_term_instance_contract ?(in_post = false) (env : env) (inst_name : ident)
    (node_name : ident) (inputs : ident list)
    (contract : Kernel_guided_contract.exported_summary_contract) (f : ltl) : Ptree.term =
  let go = compile_ltl_term_instance_contract ~in_post env inst_name node_name inputs contract in
  match f with
  | LTrue -> mk_term Ttrue
  | LFalse -> mk_term Tfalse
  | LAtom a ->
      compile_fo_term_instance_contract ~in_post env inst_name node_name inputs contract a
  | LNot a -> mk_term (Tnot (go a))
  | LAnd (a, b) -> term_bool_binop Dterm.DTand (go a) (go b)
  | LOr (a, b) -> term_bool_binop Dterm.DTor (go a) (go b)
  | LImp (a, b) -> term_bool_binop Dterm.DTimplies (go a) (go b)
  | LX _ | LG _ | LW _ -> mk_term Ttrue

let term_of_outputs (env : env) (outputs : vdecl list) : Ptree.term option =
  match outputs with
  | [] -> None
  | [ v ] -> Some (term_of_var env v.vname)
  | vs -> Some (mk_term (Ttuple (List.map (fun v -> term_of_var env v.vname) vs)))

let compile_hexpr ?(old = false) ?(prefer_link = false) ?(in_post = false) (env : env) (h : hexpr) :
    Ptree.term =
  let is_const_iexpr (e : iexpr) =
    match e.iexpr with
    | ILitInt _ | ILitBool _ -> true
    | IVar name ->
        let len = String.length name in
        len >= 4
        && String.sub name 0 3 = "Aut"
        && String.for_all (function '0' .. '9' -> true | _ -> false) (String.sub name 3 (len - 3))
    | _ -> false
  in
  match (find_link env h, prefer_link) with
  | Some id, true ->
      let t = mk_term (term_var env id) in
      if old then term_old t else t
  | _ -> begin
      match h with
      | HNow e ->
          let t = compile_term env e in
          let use_old = old && not (is_const_iexpr e) in
          if use_old then term_old t else t
      | HPreK (_e, k) -> begin
          match find_pre_k env h with
          | None -> failwith "pre_k not registered"
          | Some info ->
              if k <= 0 || k > List.length info.names then
                failwith "pre_k slot out of bounds"
              else
                let name = List.nth info.names (k - 1) in
              term_of_var env name
        end
    end

let compile_fo_term ?(prefer_link = false) (env : env) (f : fo_atom) : Ptree.term =
  match f with
  | FRel (h1, r, h2) ->
      mk_term
        (Tinnfix
           ( compile_hexpr ~prefer_link env h1,
             infix_ident (relop_id r),
             compile_hexpr ~prefer_link env h2 ))
  | FPred (id, hs) -> mk_term (Tidapp (qid1 id, List.map (compile_hexpr ~prefer_link env) hs))

let compile_fo_term_shift ?(prefer_link = false) ?(in_post = false) (env : env) (old : bool)
    (f : fo_atom) : Ptree.term =
  match f with
  | FRel (h1, r, h2) ->
      mk_term
        (Tinnfix
           ( compile_hexpr ~old ~prefer_link ~in_post env h1,
             infix_ident (relop_id r),
             compile_hexpr ~old ~prefer_link ~in_post env h2 ))
  | FPred (id, hs) ->
      mk_term (Tidapp (qid1 id, List.map (compile_hexpr ~old ~prefer_link ~in_post env) hs))

let rec compile_local_ltl_term ?(prefer_link = false) ?(in_post = false) (env : env) (f : ltl) :
    Ptree.term =
  match f with
  | LTrue -> mk_term Ttrue
  | LFalse -> mk_term Tfalse
  | LNot a -> mk_term (Tnot (compile_local_ltl_term ~prefer_link ~in_post env a))
  | LAnd (a, b) ->
      term_bool_binop Dterm.DTand
        (compile_local_ltl_term ~prefer_link ~in_post env a)
        (compile_local_ltl_term ~prefer_link ~in_post env b)
  | LOr (a, b) ->
      term_bool_binop Dterm.DTor
        (compile_local_ltl_term ~prefer_link ~in_post env a)
        (compile_local_ltl_term ~prefer_link ~in_post env b)
  | LImp (a, b) ->
      term_bool_binop Dterm.DTimplies
        (compile_local_ltl_term ~prefer_link ~in_post env a)
        (compile_local_ltl_term ~prefer_link ~in_post env b)
  | LAtom fo -> compile_fo_term_shift ~prefer_link ~in_post env false fo
  | LX _ | LG _ | LW _ ->
      failwith "compile_local_ltl_term: residual temporal operator in IR contract"

let pre_k_source_expr (env : env) (e : iexpr) : Ptree.expr =
  match e.iexpr with
  | IVar x -> field env x
  | _ -> failwith "pre_k expects a variable as first argument"

let pre_k_source_term (env : env) (e : iexpr) : Ptree.term =
  match e.iexpr with
  | IVar x -> term_of_var env x
  | _ -> failwith "pre_k expects a variable as first argument"
