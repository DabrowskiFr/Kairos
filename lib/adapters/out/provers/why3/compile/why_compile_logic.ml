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


(** Why3 logical formula operations, declarations, and pure functions. *)

open Why3
open Ptree
open Core_syntax
open Why_compile_expr
open Why_compile_ptree_helpers

let is_definition_postcondition
    (body : Core_syntax.history_free Core_syntax.hexpr)
    (ens : Core_syntax.history_free Core_syntax.hexpr) :
    bool =
  match ens.hexpr with
  | HCmp (REq, { hexpr = HVar "result"; _ }, rhs)
  | HCmp (REq, rhs, { hexpr = HVar "result"; _ }) ->
      Core_fo_simplifier.simplify
        (Core_syntax.historical_of_history_free rhs)
      = Core_fo_simplifier.simplify
          (Core_syntax.historical_of_history_free body)
  | _ -> false

let compile_pure_function_decl (f : pure_function_decl) : Ptree.decl =
  let env = { rec_name = ""; rec_vars = []; used_inputs = None } in
  let binders =
    List.map
      (fun (v : vdecl) ->
        (loc, Some (ident v.vname), false, Some (default_pty v.vty)))
      f.function_params
  in
  let body_hexpr = Core_syntax_builders.hexpr_of_expr f.function_body in
  let drop_definition_contract =
    f.function_requires = []
    && List.for_all (is_definition_postcondition body_hexpr) f.function_ensures
  in
  let mk_post t =
    (loc, [ ({ pat_desc = Pvar (ident "result"); pat_loc = loc }, t) ])
  in
  let spc =
    if drop_definition_contract then empty_spec ()
    else
      {
        Ptree.sp_pre =
          List.map (compile_hexpr env) f.function_requires;
        sp_post =
          List.map
            (fun ens -> mk_post (compile_hexpr env ens))
            f.function_ensures;
        sp_xpost = [];
        sp_reads = [];
        sp_writes = [];
        sp_alias = [];
        sp_variant = [];
        sp_checkrw = false;
        sp_diverge = false;
        sp_partial = false;
      }
  in
  let fn =
    mk_expr
      (Efun
         ( binders,
           Some (default_pty f.function_return),
           { pat_desc = Pwild; pat_loc = loc },
           Ity.MaskVisible,
           spc,
           compile_expr env f.function_body ))
  in
  Ptree.Dlet (ident f.function_name, false, Expr.RKfunc, fn)
