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
open Support

let is_mon_state_ctor (name : ident) : bool =
  let len = String.length name in
  len >= 4
  && String.sub name 0 3 = "Aut"
  && String.for_all (function '0' .. '9' -> true | _ -> false) (String.sub name 3 (len - 3))

let rec compile_iexpr (env : env) (e : iexpr) : Ptree.expr =
  let match_mon_state_eq ctor other is_eq =
    let scrut = compile_iexpr env other in
    let pat = { pat_desc = Papp (qid1 ctor, []); pat_loc = loc } in
    let tru = mk_expr Etrue in
    let fls = mk_expr Efalse in
    let then_e, else_e = if is_eq then (tru, fls) else (fls, tru) in
    mk_expr (Ematch (scrut, [ (pat, then_e); ({ pat_desc = Pwild; pat_loc = loc }, else_e) ], []))
  in
  match e.iexpr with
  | ILitInt n -> mk_expr (Econst (Constant.int_const (BigInt.of_int n)))
  | ILitBool b -> mk_expr (if b then Etrue else Efalse)
  | IVar x ->
      if is_rec_var env x then field env x
      else if is_mon_state_ctor x then mk_expr (Eidapp (qid1 x, []))
      else mk_expr (Eident (qid1 x))
  | IPar e -> compile_iexpr env e
  | IUn (Neg, a) -> mk_expr (Eidapp (qid1 "(-)", [ compile_iexpr env a ]))
  | IUn (Not, a) -> mk_expr (Enot (compile_iexpr env a))
  | IBin (((Eq | Neq) as op), a, b) -> begin
      match (as_var a, as_var b) with
      | Some va, Some vb when is_mon_state_ctor va || is_mon_state_ctor vb ->
          if is_mon_state_ctor va && is_mon_state_ctor vb then
            let same = va = vb in
            let is_eq = match op with Eq -> true | Neq -> false | _ -> true in
            mk_expr (if same = is_eq then Etrue else Efalse)
          else
            let ctor, other = if is_mon_state_ctor va then (va, mk_var vb) else (vb, mk_var va) in
            match_mon_state_eq ctor other (op = Eq)
      | _ -> mk_expr (Einnfix (compile_iexpr env a, infix_ident (binop_id op), compile_iexpr env b))
    end
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

let compile_hexpr_instance ?(in_post = false) (env : env) (inst_name : ident) (node_name : ident)
    (inputs : ident list) (pre_k_map : (hexpr * pre_k_info) list) (h : hexpr) : Ptree.term =
  match h with
  | HNow e -> compile_term_instance env inst_name node_name inputs e
  | HPreK (e, _) -> begin
      match List.find_map (fun (h', info) -> if h' = h then Some info else None) pre_k_map with
      | None -> failwith "pre_k not registered (instance)"
      | Some info ->
          let name = List.nth info.names (List.length info.names - 1) in
          term_of_instance_var env inst_name node_name name
    end

let rec compile_fo_term_instance ?(in_post = false) (env : env) (inst_name : ident)
    (node_name : ident) (inputs : ident list) (pre_k_map : (hexpr * pre_k_info) list) (f : fo) :
    Ptree.term =
  match f with
  | FTrue -> mk_term Ttrue
  | FFalse -> mk_term Tfalse
  | FRel (h1, r, h2) ->
      mk_term
        (Tinnfix
           ( compile_hexpr_instance ~in_post env inst_name node_name inputs pre_k_map h1,
             infix_ident (relop_id r),
             compile_hexpr_instance ~in_post env inst_name node_name inputs pre_k_map h2 ))
  | FPred (id, hs) ->
      mk_term
        (Tidapp
           ( qid1 id,
             List.map (compile_hexpr_instance ~in_post env inst_name node_name inputs pre_k_map) hs
           ))
  | FNot a ->
      mk_term (Tnot (compile_fo_term_instance ~in_post env inst_name node_name inputs pre_k_map a))
  | FAnd (a, b) ->
      mk_term
        (Tbinop
           ( compile_fo_term_instance ~in_post env inst_name node_name inputs pre_k_map a,
             Dterm.DTand,
             compile_fo_term_instance ~in_post env inst_name node_name inputs pre_k_map b ))
  | FOr (a, b) ->
      mk_term
        (Tbinop
           ( compile_fo_term_instance ~in_post env inst_name node_name inputs pre_k_map a,
             Dterm.DTor,
             compile_fo_term_instance ~in_post env inst_name node_name inputs pre_k_map b ))
  | FImp (a, b) ->
      mk_term
        (Tbinop
           ( compile_fo_term_instance ~in_post env inst_name node_name inputs pre_k_map a,
             Dterm.DTimplies,
             compile_fo_term_instance ~in_post env inst_name node_name inputs pre_k_map b ))

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
          if old && not (is_const_iexpr e) then term_old t else t
      | HPreK (_e, _) -> begin
          match find_pre_k env h with
          | None -> failwith "pre_k not registered"
          | Some info ->
              let name = List.nth info.names (List.length info.names - 1) in
              term_of_var env name
        end
    end

let rec compile_fo_term ?(prefer_link = false) (env : env) (f : fo) : Ptree.term =
  match f with
  | FTrue -> mk_term Ttrue
  | FFalse -> mk_term Tfalse
  | FRel (h1, r, h2) ->
      mk_term
        (Tinnfix
           ( compile_hexpr ~prefer_link env h1,
             infix_ident (relop_id r),
             compile_hexpr ~prefer_link env h2 ))
  | FPred (id, hs) -> mk_term (Tidapp (qid1 id, List.map (compile_hexpr ~prefer_link env) hs))
  | FNot a -> mk_term (Tnot (compile_fo_term ~prefer_link env a))
  | FAnd (a, b) ->
      mk_term
        (Tbinop (compile_fo_term ~prefer_link env a, Dterm.DTand, compile_fo_term ~prefer_link env b))
  | FOr (a, b) ->
      mk_term
        (Tbinop (compile_fo_term ~prefer_link env a, Dterm.DTor, compile_fo_term ~prefer_link env b))
  | FImp (a, b) ->
      mk_term
        (Tbinop
           (compile_fo_term ~prefer_link env a, Dterm.DTimplies, compile_fo_term ~prefer_link env b))

let rec compile_ltl_term_shift ?(prefer_link = false) ?(in_post = false) (env : env) (shift : int)
    (f : fo_ltl) : Ptree.term =
  let shift = if shift <= 0 then 0 else 1 in
  match f with
  | LTrue -> mk_term Ttrue
  | LFalse -> mk_term Tfalse
  | LNot a -> mk_term (Tnot (compile_ltl_term_shift ~prefer_link ~in_post env shift a))
  | LAnd (a, b) ->
      mk_term
        (Tbinop
           ( compile_ltl_term_shift ~prefer_link ~in_post env shift a,
             Dterm.DTand,
             compile_ltl_term_shift ~prefer_link ~in_post env shift b ))
  | LOr (a, b) ->
      mk_term
        (Tbinop
           ( compile_ltl_term_shift ~prefer_link ~in_post env shift a,
             Dterm.DTor,
             compile_ltl_term_shift ~prefer_link ~in_post env shift b ))
  | LImp (a, b) ->
      mk_term
        (Tbinop
           ( compile_ltl_term_shift ~prefer_link ~in_post env shift a,
             Dterm.DTimplies,
             compile_ltl_term_shift ~prefer_link ~in_post env shift b ))
  | LX a -> compile_ltl_term_shift ~prefer_link ~in_post env 1 a
  | LG a -> compile_ltl_term_shift ~prefer_link ~in_post env shift a
  | LW (a, b) ->
      compile_ltl_term_shift ~prefer_link ~in_post env shift
        (LOr (b, LAnd (a, LX (LW (a, b)))))
  | LAtom f ->
      let old = shift = 0 in
      compile_fo_term_shift ~prefer_link ~in_post env old f

and compile_fo_term_shift ?(prefer_link = false) ?(in_post = false) (env : env) (old : bool)
    (f : fo) : Ptree.term =
  match f with
  | FTrue -> mk_term Ttrue
  | FFalse -> mk_term Tfalse
  | FRel (h1, r, h2) ->
      mk_term
        (Tinnfix
           ( compile_hexpr ~old ~prefer_link ~in_post env h1,
             infix_ident (relop_id r),
             compile_hexpr ~old ~prefer_link ~in_post env h2 ))
  | FPred (id, hs) ->
      mk_term (Tidapp (qid1 id, List.map (compile_hexpr ~old ~prefer_link ~in_post env) hs))
  | FNot a -> mk_term (Tnot (compile_fo_term_shift ~prefer_link ~in_post env old a))
  | FAnd (a, b) ->
      mk_term
        (Tbinop
           ( compile_fo_term_shift ~prefer_link ~in_post env old a,
             Dterm.DTand,
             compile_fo_term_shift ~prefer_link ~in_post env old b ))
  | FOr (a, b) ->
      mk_term
        (Tbinop
           ( compile_fo_term_shift ~prefer_link ~in_post env old a,
             Dterm.DTor,
             compile_fo_term_shift ~prefer_link ~in_post env old b ))
  | FImp (a, b) ->
      mk_term
        (Tbinop
           ( compile_fo_term_shift ~prefer_link ~in_post env old a,
             Dterm.DTimplies,
             compile_fo_term_shift ~prefer_link ~in_post env old b ))

let rel_hexpr (env : env) (h : hexpr) : hexpr =
  match h with HNow e -> HNow e | HPreK (e, k) -> HPreK (e, k)

let rec ltl_relational (env : env) (f : fo_ltl) : fo_ltl =
  match f with
  | LTrue | LFalse -> f
  | LNot a -> LNot (ltl_relational env a)
  | LAnd (a, b) -> LAnd (ltl_relational env a, ltl_relational env b)
  | LOr (a, b) -> LOr (ltl_relational env a, ltl_relational env b)
  | LImp (a, b) -> LImp (ltl_relational env a, ltl_relational env b)
  | LX a -> LX (ltl_relational env a)
  | LG a -> LG (ltl_relational env a)
  | LW (a, b) -> LW (ltl_relational env a, ltl_relational env b)
  | LAtom f -> LAtom (rel_fo env f)

and rel_fo (env : env) (f : fo) : fo =
  match f with
  | FTrue | FFalse -> f
  | FRel (h1, r, h2) -> FRel (rel_hexpr env h1, r, rel_hexpr env h2)
  | FPred (id, hs) -> FPred (id, List.map (rel_hexpr env) hs)
  | FNot a -> FNot (rel_fo env a)
  | FAnd (a, b) -> FAnd (rel_fo env a, rel_fo env b)
  | FOr (a, b) -> FOr (rel_fo env a, rel_fo env b)
  | FImp (a, b) -> FImp (rel_fo env a, rel_fo env b)

type spec_frag = { pre : Ptree.term list; post : Ptree.term list }

let empty_frag : spec_frag = { pre = []; post = [] }

let ltl_spec (env : env) (f : fo_ltl) : spec_frag =
  let rec has_x = function
    | LX _ -> true
    | LTrue | LFalse | LAtom _ -> false
    | LNot a | LG a -> has_x a
    | LAnd (a, b) | LOr (a, b) | LImp (a, b) | LW (a, b) -> has_x a || has_x b
  in
  let post_term f =
    if has_x f then compile_ltl_term_shift ~prefer_link:true ~in_post:true env 0 f
    else compile_ltl_term_shift ~prefer_link:true ~in_post:true env 1 f
  in
  match f with
  | LTrue -> empty_frag
  | LFalse -> { pre = []; post = [ mk_term Tfalse ] }
  | LNot _ | LAnd _ | LOr _ | LImp _ | LAtom _ | LX _ | LW _ ->
      let pre_t = compile_ltl_term_shift ~prefer_link:true ~in_post:false env 1 f in
      let post_t = post_term f in
      { pre = [ pre_t ]; post = [ post_t ] }
  | LG a ->
      let pre_t = compile_ltl_term_shift ~prefer_link:true ~in_post:false env 1 a in
      let post_t = post_term a in
      { pre = [ pre_t ]; post = [ post_t ] }

let pre_k_source_expr (env : env) (e : iexpr) : Ptree.expr =
  match e.iexpr with
  | IVar x -> field env x
  | _ -> failwith "pre_k expects a variable as first argument"

let pre_k_source_term (env : env) (e : iexpr) : Ptree.term =
  match e.iexpr with
  | IVar x -> term_of_var env x
  | _ -> failwith "pre_k expects a variable as first argument"
