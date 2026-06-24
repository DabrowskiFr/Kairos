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
open Why_compile_logic_formula

let logic_getter_decl ~(env : Why_compile_expr.env) (vname : ident) (vty : ty) :
    Ptree.decl =
  let field_name = vname in
  let getter_name = ident ("logic_" ^ field_name) in
  let param : Ptree.param =
    (loc, Some (ident "self"), false, Ptree.PTtyapp (qid1 "vars", []))
  in
  let body = term_of_var { env with rec_name = "self" } field_name in
  Ptree.Dlogic
    [
      {
        ld_loc = loc;
        ld_ident = getter_name;
        ld_params = [ param ];
        ld_type = Some (default_pty vty);
        ld_def = Some body;
      };
    ]

let logic_bool_pred_decl ~(env : Why_compile_expr.env)
    ~(input_ports : Why_runtime_view.port_view list) ~(name : string)
    ~(formula : Core_syntax.hexpr) : Ptree.decl =
  let env = { env with rec_name = "self" } in
  let self_param : Ptree.param =
    (loc, Some (ident "self"), false, Ptree.PTtyapp (qid1 "vars", []))
  in
  let input_params =
    List.map
      (fun (p : Why_runtime_view.port_view) ->
        (loc, Some (ident p.port_name), false, default_pty p.port_type))
      input_ports
  in
  let body =
    Why_compile_expr.compile_local_fo_formula_term env
      (balance_boolean_hexpr formula)
  in
  Ptree.Dlogic
    [
      {
        ld_loc = loc;
        ld_ident = ident name;
        ld_params = self_param :: input_params;
        ld_type = None;
        ld_def = Some body;
      };
    ]

let logic_bool_pred_decl_with_params ~(env : Why_compile_expr.env)
    ~(params : (ident * Ptree.pty) list) ~(name : string)
    ~(formula : Core_syntax.hexpr) : Ptree.decl =
  let env = { env with rec_name = "self" } in
  let self_param : Ptree.param =
    (loc, Some (ident "self"), false, Ptree.PTtyapp (qid1 "vars", []))
  in
  let params =
    List.map (fun (name, pty) -> (loc, Some (ident name), false, pty)) params
  in
  let body =
    Why_compile_expr.compile_local_fo_formula_term env
      (balance_boolean_hexpr formula)
  in
  Ptree.Dlogic
    [
      {
        ld_loc = loc;
        ld_ident = ident name;
        ld_params = self_param :: params;
        ld_type = None;
        ld_def = Some body;
      };
    ]

let logic_bool_pred_decl_with_body ~use_self
    ~(params : (ident * Ptree.pty) list) ~(name : string) ~(body : Ptree.term) :
    Ptree.decl =
  let self_param : Ptree.param =
    (loc, Some (ident "self"), false, Ptree.PTtyapp (qid1 "vars", []))
  in
  let params =
    List.map (fun (name, pty) -> (loc, Some (ident name), false, pty)) params
  in
  Ptree.Dlogic
    [
      {
        ld_loc = loc;
        ld_ident = ident name;
        ld_params = (if use_self then self_param :: params else params);
        ld_type = None;
        ld_def = Some body;
      };
    ]

let port_view_to_vdecl (p : Why_runtime_view.port_view) : vdecl =
  { vname = p.port_name; vty = p.port_type }
