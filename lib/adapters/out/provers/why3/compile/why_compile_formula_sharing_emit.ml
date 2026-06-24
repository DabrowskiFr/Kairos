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
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * General Public License for more details.
 *
 * You should have received a copy of the GNU General Public License
 * along with this program.  If not, see <https://www.gnu.org/licenses/>.
 *---------------------------------------------------------------------------*)

open Why3
open Ptree
open Core_syntax
open Why_compile_expr
open Why_compile_logic
open Why_compile_ptree_helpers

module Inventory = Why_compile_formula_sharing_inventory

type shared_entry = Inventory.shared_entry
type shared_formula_decl = string * Core_syntax.hexpr * Ptree.decl

let shared_formula_call_with_rec rec_name name params use_self =
  let args =
    (if use_self then [ mk_term (Tident (qid1 rec_name)) ] else [])
    @ List.map (fun (param_name, _) -> mk_term (Tident (qid1 param_name))) params
  in
  mk_term (Tidapp (qid1 name, args))

let rec compile_shared_hexpr env table current_key rec_name formula =
  let key = Inventory.formula_key formula in
  match Hashtbl.find_opt table key with
  | Some (name, params, _, use_self) when not (String.equal key current_key) ->
      shared_formula_call_with_rec rec_name name params use_self
  | _ ->
      let local_env = { env with rec_name } in
      begin
        match formula.hexpr with
        | HLitInt n -> mk_term (Tconst (Constant.int_const (BigInt.of_int n)))
        | HLitBool b -> mk_term (if b then Ttrue else Tfalse)
        | HLitEnum c -> mk_term (Tident (qid1 c))
        | HVar x -> mk_term (term_var local_env x)
        | HPreK (_name, _k) ->
            failwith
              "compile_shared_hexpr: residual HPreK in Why3 emission input"
        | HUn (Neg, a) ->
            mk_term
              (Tidapp
                 ( qid1 "(-)",
                   [ compile_shared_hexpr env table current_key rec_name a ] ))
        | HUn (Not, a) ->
            mk_term (Tnot (compile_shared_hexpr env table current_key rec_name a))
        | HPred (id, hs) ->
            mk_term
              (Tidapp
                 ( qid1 id,
                   List.map
                     (compile_shared_hexpr env table current_key rec_name)
                     hs ))
        | HFunCall (fn, hs) ->
            mk_term
              (Tidapp
                 ( qid1 fn,
                   List.map
                     (compile_shared_hexpr env table current_key rec_name)
                     hs ))
        | HBin (And, a, b) ->
            term_bool_binop Dterm.DTand
              (compile_shared_hexpr env table current_key rec_name a)
              (compile_shared_hexpr env table current_key rec_name b)
        | HBin (Or, a, b) ->
            term_bool_binop Dterm.DTor
              (compile_shared_hexpr env table current_key rec_name a)
              (compile_shared_hexpr env table current_key rec_name b)
        | HBin (op, a, b) ->
            mk_term
              (Tinnfix
                 ( compile_shared_hexpr env table current_key rec_name a,
                   infix_ident (binop_id op),
                   compile_shared_hexpr env table current_key rec_name b ))
        | HCmp (op, a, b) ->
            mk_term
              (Tinnfix
                 ( compile_shared_hexpr env table current_key rec_name a,
                   infix_ident (relop_id op),
                   compile_shared_hexpr env table current_key rec_name b ))
      end

let build_shared_formula_entries ~env ~table ~order =
  order
  |> List.sort (fun (_, _, _, size_a) (_, _, _, size_b) ->
         Int.compare size_a size_b)
  |> List.map (fun (name, params, formula, _) ->
         let body =
           compile_shared_hexpr env table (Inventory.formula_key formula) "self"
             formula
         in
         let decl =
           logic_bool_pred_decl_with_body
             ~use_self:(Inventory.formula_uses_self env formula)
             ~params ~name ~body
         in
         (name, formula, decl))
